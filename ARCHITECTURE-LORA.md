# TPWater Architecture — LoRa/Meshtastic Redesign

## Overview

Remote sensor nodes are replaced with Heltec V4 (ESP32-S3 + SX1262) devices running
custom Meshtastic firmware. The hub remains a Raspberry Pi running the existing Tcl
stack, now with an MQTT interface via mosquitto.

## Topology

```
[Field Heltec]                 [Field Heltec]
 reads MCP342x                  reads MCP342x
 controls switches              controls switches
 publishes → LoRa               publishes → LoRa
 subscribes ← LoRa              subscribes ← LoRa
       |                              |
       └──────── LoRa mesh ───────────┘
                      |
              [Gateway Heltec]
               Meshtastic MQTT bridge
               Pi local WiFi
                      |
                 [Pi mosquitto]
                      |
                 [hub.tcl]
                  subscribes sensor topics
                  publishes command topics
```

## Components

### Field Nodes — Heltec WiFi LoRa 32 V4

- **MCU**: ESP32-S3
- **Radio**: SX1262 (LoRa 915 MHz)
- **Display**: OLED (local status)
- **Firmware**: Meshtastic with custom sensor/control additions
- **Primary transport**: LoRa — WiFi not used in the field
- **Sensors**: MCP342x or ADS1115 via I2C (flow, tank level, analog inputs)
- **Outputs**: GPIO switch control (pumps, valves)
- **Mesh relay**: every node relays for others — nodes out of direct range of the
  gateway reach it through intermediate nodes (Meshtastic managed flood, default 3 hops)

### Gateway Node — Heltec WiFi LoRa 32 V4

- Co-located with the Pi hub
- Runs standard Meshtastic in MQTT gateway mode
- Connects to Pi via local WiFi
- Bridges mesh ↔ mosquitto bidirectionally:
  - Sensor data: mesh → mosquitto
  - Commands: mosquitto → mesh → field nodes

### Hub — Raspberry Pi

- **Broker**: mosquitto on standard port 1883
- **Application**: hub.tcl (replaces `jbr::msg` with MQTT subscribe/publish)
- **Database**: SQLite unchanged — same schema, same rolling GPM, same rules engine
- **HTTP**: wapp server unchanged — same web UI and REST API
- **Notifications**: Twilio SMS unchanged

## Protocol / Topic Structure

Topics follow the pattern `tpwater/<station>/<measurement>`:

| Direction | Topic | Payload |
|-----------|-------|---------|
| node → hub | `tpwater/waterplant/flow` | float |
| node → hub | `tpwater/waterplant/tank` | float |
| node → hub | `tpwater/golfcourse/golf` | float |
| hub → node | `tpwater/waterplant/golf/set` | 0 or 1 |
| hub → node | `tpwater/waterplant/thrd/set` | 0 or 1 |

## Custom Meshtastic Firmware

Standard Meshtastic does not support MCP342x or ADS1115. Field node firmware requires
two additions:

1. **Sensor driver** — MCP342x (and/or ADS1115) I2C ADC added to the Meshtastic
   telemetry module. Publishes calibrated readings on the configured interval.

2. **Switch control** — subscribes to command topics via the mesh, toggles GPIO
   outputs (pumps, valves) on receipt.

Gateway node runs unmodified Meshtastic firmware.

## Hub Changes

`hub.tcl` replaces `jbr::msg` with MQTT:

| Current (`jbr::msg`) | New (MQTT) |
|---|---|
| `msg_server WATER` | mosquitto (system service) |
| `msg_publish WATER $name` | publish to `tpwater/station/name` |
| `msg_srvproc WATER rec` | subscribe to sensor topics |
| `msg_apikey` auth | mosquitto ACLs |
| `msg_setreopen` reconnect | MQTT built-in keepalive |

Rules, SQLite, wapp HTTP, and Twilio are unchanged.

## Site RF Planning — `los/los.py`

Pre-deployment LOS/Fresnel analyzer. Takes a Google Earth KML of node locations,
fetches NED 10m terrain elevation from OpenTopoData, and produces a pairwise link
report with combined RF margin accounting for path loss, foliage, and terrain
diffraction.

**Radio parameters (Heltec V4 defaults):**
- TX: 28 dBm (onboard PA over SX1262 native 22 dBm)
- RX sensitivity: −148 dBm (SX1262 at SF12)
- Link budget: 176 dB
- Foliage model: 0.3 dB/m × 30m terminal depth × 2 ends = 18 dB (constant)
- Diffraction: ITU-R P.526 knife-edge at worst obstruction point

**Usage:**
```bash
./los/los.py list                                   # show placemarks + extended attrs
./los/los.py set "Gate House" antenna_height 6      # write per-node antenna height to KML
./los/los.py analyze                                # full link report + connectivity
./los/los.py analyze --fade-margin 10               # require 10 dB reliability margin
```

Antenna heights stored as `<ExtendedData>` in the KML file; fall back to
`--antenna-height` default (3 m) when not set.

Elevation responses cached in `los/elevation_cache.json` — subsequent runs are instant.

**Site findings (TWP-LOS.kml, 9 nodes):**

All 9 nodes form a single connected mesh at SF12 with the Heltec V4.
Minimum margin across all links: ~38 dB (Water Plant → Golf Course Well, 1.36 km,
36 m Fresnel obstruction, 25 dB knife-edge loss). Most links are 55–90 dB.

**Link reliability by margin:**

| Margin | Assessment |
|--------|------------|
| > 50 dB | Essentially bulletproof |
| 35–50 dB | Reliable; survives summer foliage + model error |
| 20–35 dB | Workable; validate on-site, consider raising antenna |
| < 20 dB | Risky; field test required |

Real-world factors that consume margin: seasonal foliage variation (5–15 dB),
terrain model error (2–5 dB), antenna mismatch (2–5 dB), multipath fading (3–10 dB).
Worst-case stack ~30 dB, so 38 dB is reliable but worth a field RSSI check on the
Water Plant → Golf Course Well path specifically, as its diffraction model is
sensitive to small terrain errors (36 m obstruction depth).

**Mesh flood behavior and hop count:**

Meshtastic uses managed flood with duplicate suppression (not spanning tree). Each
packet is rebroadcast once per node; duplicates are dropped by packet ID. There is
no production-ready distance-vector or link-state protocol available yet.

With strong mutual visibility across all deployed nodes, a single transmission
generates several rebroadcasts — the gateway receives the packet via multiple paths,
improving reliability. The hub sees one MQTT delivery regardless.

**Hop count:** Leave at the default of 3 for initial deployment. Given the link
margins, all nodes can reach the gateway in 1 hop under normal conditions; 2 hops
covers any single-node failure. Reduce to 2 hops only if congestion symptoms appear
(missed packets, retries).

**Node count:** The KML analysis included extra nodes added for LOS coverage
evaluation. Fewer deployed nodes means fewer rebroadcasts per packet and lower
channel occupancy — prefer a minimal node count that maintains mesh connectivity.

**Airtime:** At SF12, each packet occupies ~1–2 s. If congestion becomes an issue,
dropping to SF10 or SF9 (after confirming RSSI in the field) cuts airtime 4–8×,
which is more effective than reducing hop count. Stagger sensor report intervals
across nodes to avoid simultaneous transmissions.

## Field Validation

Meshtastic nodes report RSSI (dBm) and SNR (dB) for every received packet via the
SX1262 hardware. These are available on the Heltec OLED display, the Meshtastic
mobile app (mesh map view), and in the MQTT JSON envelope (`rx_rssi`, `rx_snr`
fields on every gateway-bridged packet).

**Validating `los.py` predictions:**

Expected RSSI for a link can be read directly from the analysis output:

```
Expected RSSI ≈ RX_sensitivity + Margin
              = −148 + margin_db  (dBm)
```

| Predicted margin | Expected RSSI |
|-----------------|---------------|
| 38 dB (worst link) | −110 dBm |
| 55 dB (typical) | −93 dBm |
| 75 dB (clear LOS) | −73 dBm |

If measured RSSI is better than predicted, the terrain model is conservative. If
worse, the DEM underestimates obstruction — consider raising antenna height.

Monitor the MQTT stream during the field test to collect per-link RSSI/SNR for all
node pairs. Pay particular attention to Water Plant → Golf Course Well (predicted
−110 dBm), the link most sensitive to terrain model error.

## Status

- [ ] Radio range test on site — **do this first**
- [ ] Meshtastic mesh relay test (multi-hop)
- [ ] MCP342x sensor driver for Meshtastic
- [ ] Switch control handler for Meshtastic
- [ ] `jbr::mqtt` package (or vendored Tcl MQTT client)
- [ ] Hub MQTT integration (replace `jbr::msg` calls)
- [ ] End-to-end test: sensor → LoRa → gateway → mosquitto → hub.tcl
- [ ] Command path test: hub.tcl → mosquitto → gateway → mesh → field node GPIO
