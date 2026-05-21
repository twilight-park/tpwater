# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

TPWater is a distributed water system monitoring and control application for Twilight Park. It runs a hub server at `data.rkroll.com` and multiple Raspberry Pi client stations that read sensors (flow meters, tank levels) and control outputs (pumps, valves) via I2C and GPIO.

## Running the Service

```bash
./tpwater.sh start|stop|restart|stat|tail
```

The script auto-detects hub vs. client mode: if `~/apikey` exists, it runs as a client; otherwise as hub.

**Hub:** `hub/tpwater-hub.tcl` on port 8001 (MSG) and 7777 (HTTP)  
**Client:** `client/tpwater-client.tcl`, connects to `data.rkroll.com:8001`, HTTP on 7777

**Query the database directly:**
```bash
tclsh query.tcl tpwater.db waterplant -1h now
```

## Architecture

**Hub-spoke message passing:** The `jbr::msg` library implements a publish/subscribe protocol. The hub runs `msg_server WATER` on port 8001; clients connect with `msg_client WATER`. Variables are published as named topics — clients subscribe to names they don't own and publish their sensor readings via `msg_cmd WATER "rec $seconds $values"`.

**Channel abstraction (`share/lib/channel.tcl`):** Each sensor is a `channel` OO object with `zero`, `scale`, `min`, `max`, `precision` calibration params. `$name scaled $value` applies the ADC-to-engineering-units conversion.

**Config-driven devices (`share/config/*.cfg`):** Each physical station has a `.cfg` file (e.g. `waterplant.cfg`, `golfcourse.cfg`) listing its `apikey`, `record` period, and named channels with device type (`MCP342x`, `ADS1115`, `gpio`), bus/address/channel, and calibration. The hub uses these to map API keys to station names and know which names belong to which station.

**Database:** SQLite at `tpwater.db`. Schema in `hub/db-setup.tcl` with tables per station (`waterplant`, `golfcourse`, `thirdlevel`, `radio`). `migrate-db` handles schema evolution. `rolling_gpm` computes moving-window flow averages for leak detection.

**Rules (`hub/rules.tcl`):** Simple `every`/`cron` callbacks with `try-rule NAME { ... }`. Rules read/write global Tcl vars (e.g. `$::tank`, `$::golf:request`) which are also msg topics. Setting `$::name:request` on the hub triggers `set-state`, which propagates the output command to the owning client via the message bus.

**Notifications (`hub/notify.tcl`, `hub/hub.cfg`):** SMS via Twilio. Notification types (LEAK, NOTE) are configured in `hub.cfg` with rate limiting, recipient lists, and message templates. Personal contact info comes from environment variables (`$env(PEOPLE)`).

**HTTP API (`hub/http-service.tcl`):** Uses `wapp` (local fork at `pkg/wapp/`). Routes: `GET /query/table/start/end` returns JSON time-series, `GET /query2/lookback/window/frequency` returns rolling GPM, `GET /clients` returns connected station status, `GET /press` toggles output states.

**Tcl packages:** All `jbr::*` packages live at `~/lib/tcl8/site-tcl`. Key ones: `jbr::msg` (message bus), `jbr::cron` (cron scheduler), `jbr::seconds` (relative time parsing like `-1h`, `10.5m`), `jbr::unix` (shell utils), `jbr::template` (SQL templating).

## Key Files

| File | Purpose |
|------|---------|
| `hub/tpwater-hub.tcl` | Hub entry point: starts msg server, loads configs, runs event loop |
| `client/tpwater-client.tcl` | Client entry point: reads sensors, publishes to hub |
| `hub/rules.tcl` | Automation rules (pump control, leak detection) |
| `hub/hub.cfg` | Hub config: ports, notification definitions, known hosts |
| `share/config/*.cfg` | Per-station device/channel/calibration config |
| `share/lib/channel.tcl` | Channel OO class with scaling math |
| `hub/db-setup.tcl` | SQLite schema, migration, `db:record` proc |
| `hub/rolling_gpm.tcl` | Moving-window flow rate calculation |
| `hub/notify.tcl` | Twilio SMS notification with rate limiting |
| `tpwater.sh` | Service manager (start/stop/restart/stat/tail) |
| `bootstrap.sh` | Raspberry Pi provisioning and deployment |

## RF Site Planning — `los/los.py`

Pre-deployment LoRa link analyzer. Fetches NED 10m terrain from OpenTopoData,
computes Fresnel clearance, knife-edge diffraction loss, and combined RF margin.
Elevation results cached in `los/elevation_cache.json`.

```bash
./los/los.py list                                 # placemarks + per-node attrs
./los/los.py set "Gate House" antenna_height 6    # write antenna height into KML
./los/los.py analyze                              # pairwise link report + mesh connectivity
./los/los.py --kml path/to/file.kml analyze       # explicit KML (default: ~/Downloads/TWP-LOS.kml)
```

Antenna heights are stored as `<ExtendedData>` in the KML file and read back by
`analyze`. Any KML attribute can be set with `set`; `antenna_height` is the only
one the tool currently reads.

## Environment

Secrets are in environment variables loaded from `~/.twillio`:
- `$env(PEOPLE)` — contact list for notifications
- `$env(KNOWN_HOSTS)` / `$env(KNOWN_UUIDS)` — device alias mappings
- Client API keys are in `~/apikey` on each Pi

Logs go to `log/YYYYMMDD-tpwater-{hub,client}.log`. Crontab is at `share/scripts/crontab`.
