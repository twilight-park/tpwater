# TPWater Architecture — LoRa/Meshtastic Redesign

## Overview

Field Raspberry Pis are retained but the cellular/jbr::msg transport is replaced
with a LoRa mesh using Heltec V4 (ESP32-S3 + SX1262) devices running Meshtastic.
Each field Pi publishes sensor data to a local mosquitto broker; a co-located Heltec
bridges that data over LoRa to the hub Pi. The hub Pi runs mosquitto and hub.tcl
subscribes to it instead of jbr::msg.

## Migration Strategy

Migration is done in two phases to allow parallel validation before cutting over.

### Phase 1 — Intermediate (LoRa alongside cell)

```
Field Pi → jbr::msg → cell → hub Pi        (existing, unchanged)
Field Pi → local mosquitto
                ↑ WiFi
           Field Heltec
                ↓ LoRa mesh
           Gateway Heltec
                ↓ WiFi
           Hub mosquitto → hub.tcl (new, parallel)
```

- Field Pi publishes sensor readings to both jbr::msg and local mosquitto
- Field Heltec connects to local Pi WiFi, subscribes to local mosquitto,
  rebroadcasts over LoRa mesh
- Hub Pi runs mosquitto; hub.tcl subscribes to it in parallel with jbr::msg
- Both data streams run simultaneously — diff them to validate LoRa delivery
- No custom sensor firmware needed: Pi still reads I2C/GPIO, Heltec only bridges MQTT

**Field Heltec firmware requirement (Phase 1):** subscribe to local Pi mosquitto
over WiFi and forward topics over LoRa mesh. Simpler than full sensor driver but
still custom firmware — not stock Meshtastic.

### Phase 2 — Final (LoRa only)

```
Field Pi → local mosquitto
                ↑ WiFi
           Field Heltec
                ↓ LoRa mesh
           Gateway Heltec
                ↓ WiFi
           Hub mosquitto → hub.tcl
```

Once LoRa delivery is validated: shut down cell service, remove jbr::msg calls
from hub.tcl and client Tcl scripts.

### Final Topology

```
[Field Pi + Heltec]           [Field Pi + Heltec]
 Pi reads sensors               Pi reads sensors
 Pi → local mosquitto           Pi → local mosquitto
 Heltec bridges → LoRa          Heltec bridges → LoRa
       |                              |
       └──────── LoRa mesh ───────────┘
                      |
              [Gateway Heltec]
               Meshtastic MQTT bridge
               Pi local WiFi
                      |
                 [Hub Pi mosquitto]
                      |
                 [hub.tcl]
                  subscribes sensor topics
                  publishes command topics
```

## Components

### Field Nodes — Raspberry Pi + Heltec WiFi LoRa 32 V4

- **Pi**: reads MCP342x/ADS1115 sensors and GPIO outputs (unchanged)
- **Pi**: publishes to local mosquitto (`tpwater/<station>/<name>`)
- **Heltec MCU**: ESP32-S3
- **Heltec radio**: SX1262 (LoRa 915 MHz)
- **Heltec display**: OLED (local status)
- **Heltec firmware**: custom — subscribes to local Pi mosquitto over WiFi,
  forwards sensor topics over LoRa mesh; subscribes to command topics from mesh,
  forwards to Pi mosquitto for output control

### Gateway Node — Heltec WiFi LoRa 32 V4

- Co-located with the hub Pi
- Runs standard Meshtastic in MQTT gateway mode
- Connects to hub Pi via local WiFi
- Bridges mesh ↔ mosquitto bidirectionally:
  - Sensor data: mesh → mosquitto
  - Commands: mosquitto → mesh → field Heltecs → field Pi mosquitto

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

## Custom Heltec Firmware

Standard Meshtastic does not support the MQTT bridge role needed at field nodes.
Field node firmware requires:

1. **MQTT subscriber** — connect to local Pi WiFi, subscribe to
   `tpwater/<station>/#`, forward payloads over LoRa mesh.

2. **Command forwarder** — subscribe to command topics from mesh
   (`tpwater/<station>/+/set`), publish to local Pi mosquitto so the Pi can
   act on GPIO outputs.

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
- Diffraction: ITU-R P.526 knife-edge at worst obstruction point
- Foliage: ITU-R P.833-10 maximum excess attenuation model (see below)

**Foliage loss model (ITU-R P.833-10):**

```
A_v = A_m × (1 − exp(−d × γ / A_m))
```

Where `d` = meters of path where LOS is above terrain but within canopy height, `γ` = specific attenuation (dB/m), `A_m` = saturation limit (dB).

Defaults used: γ = 0.3 dB/m, A_m = 26.5 dB.

- **Formula source:** ITU-R P.833-10 (2021), Annex 1, Section 3 — "Maximum excess attenuation model for terrestrial paths through woodland."
- **A_m = 26.5 dB:** From P.833-10 tabulated measurement at 949 MHz (closest published frequency to 915 MHz). Tropical-tree formula from P.833-3 gives A_m = 0.18 × f^0.752 ≈ 30 dB at 915 MHz, consistent.
- **γ = 0.3 dB/m:** Within the documented 0.2–0.5 dB/m range for deciduous forest at 900 MHz (P.833-9). Slightly higher than the 0.17 dB/m measured in P.833-10 because those measurements used a 25 m TX antenna above the canopy; our 3 m antenna-within-canopy geometry is a worse case.
- **Saturation behavior:** At 75 m of forest: ~15 dB. At 225 m: ~24 dB. Beyond ~150 m the signal finds diffuse scattering paths and attenuation rate drops — modeled by exponential saturation rather than linear accumulation.
- **NLCD integration:** Path segments are only counted as foliage where `0 ≤ LOS_above_terrain < canopy_height`. Terrain-blocked segments are handled exclusively by knife-edge diffraction to avoid double-counting.
- **Empirical LoRa data:** Measured excess loss in hilly forested terrain at 920 MHz reached 40–52 dB above FSPL (includes diffraction); our separate diffraction + foliage model is consistent with this range.

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

**Site findings (TWP-LOS.kml, 6 active nodes):**

All 6 nodes form a single connected mesh at SF12 with the Heltec V4.
Minimum margin across all links: ~37 dB (Golf Course Well → Spring Cottage, 0.67 km,
20 dB knife-edge + 25 dB foliage). Most links are 43–95 dB.

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

**Node roles:** Meshtastic has no per-link disable, but node relay behavior is
configurable. Set sensor-only nodes (those with a strong direct path to the gateway)
to CLIENT role — they send and receive but do not rebroadcast for others. Only nodes
that are genuinely needed as relay hops should be ROUTER. The gateway node itself
should be ROUTER.

The flood protocol already handles poor links naturally: packets arrive via the
strongest path first; later arrivals via weaker paths are dropped as duplicates.
Disabling poor links is not necessary.

Optimization priority:
1. Minimize deployed node count
2. Set leaf/sensor nodes to CLIENT role
3. Stagger sensor report intervals across nodes
4. Reduce spreading factor (SF10/SF9) after field RSSI confirms headroom — cuts airtime 4–8× vs SF12

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

**Phase 0 — RF validation**
- [ ] Radio range test on site — **do this first**
- [ ] Meshtastic mesh relay test (multi-hop)
- [ ] Collect per-link RSSI/SNR, compare against `los.py` predictions

**Phase 1 — Intermediate (parallel operation)**
- [ ] Add mosquitto to each field Pi; publish sensor readings to local broker
- [ ] Heltec firmware: WiFi → subscribe local MQTT → forward over LoRa mesh
- [ ] Heltec firmware: receive command topics from mesh → publish to local Pi MQTT
- [ ] Hub mosquitto setup
- [ ] Hub MQTT integration in hub.tcl (parallel to existing jbr::msg)
- [ ] End-to-end test: Pi sensor → local MQTT → Heltec → LoRa → gateway → hub MQTT → hub.tcl
- [ ] Validate data matches between jbr::msg and LoRa streams

**Phase 2 — Cutover**
- [ ] Shut down cell service
- [ ] Remove jbr::msg from hub.tcl and client Tcl scripts
