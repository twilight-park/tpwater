# AGENTS.md — tpwater (rev2)

Twilight Park distributed water monitoring. Hub server + Raspberry Pi client stations reading sensors (MCP342x/ADS1115 ADCs, GPIO) over I2C, publishing to hub via `jbr::msg`, SQLite storage.

## Service & Mode

```bash
./tpwater.sh start|stop|restart|stat|tail|retail|backup
```

Auto-detects mode: **client** if `~/apikey` exists, else **hub**.  
- Hub: `hub/tpwater-hub.tcl` — msg server on port 8001, HTTP on 7777  
- Client: `client/tpwater-client.tcl` — connects to `data.rkroll.com:8001`, HTTP on 7777

## Key Environment

- `$env(WATER)` = `.:8001` (hub) or `data.rkroll.com:8001` (client) — set inside entrypoint scripts
- `$env(PEOPLE)`, `$env(KNOWN_HOSTS)`, `$env(KNOWN_UUIDS)` — loaded from `~/.twillio`
- `$TCL8_4_TM_PATH=~/lib/tcl8/site-tcl` — required for `jbr::*` packages
- Client API key: `cat ~/apikey`

## Architecture

**Hub-spoke message bus (`jbr::msg`):** Hub runs `msg_server WATER`. Clients `msg_client WATER`. Variables are published as named topics. Clients subscribe to names they don't own. Setting `$::name:request` on hub triggers `set-state` → command propagates to owning client.

**Config-driven:** Each station has a `.cfg` in `share/config/` listing `apikey`, `record` period, and named channels with device type/bus/address/channel/calibration. Hub maps API keys to station names.

**Database:** SQLite at `tpwater.db`. Schema in `hub/db-setup.tcl` — tables per station (`waterplant`, `golfcourse`, `thirdlevel`, `radio`). Schema migration via `migrate-db`. Query with: `tclsh query.tcl tpwater.db waterplant -1h now`.

**HTTP API (`hub/http-service.tcl`):** Wapp framework (local fork at `pkg/wapp/`). Key routes:
- `GET /query/{table}/{start}/{end}` — JSON time-series
- `GET /query2/{lookback}/{window}/{frequency}` — rolling GPM
- `GET /clients` — connected stations
- `GET /press?button={name}` — toggle output state

**Rules (`hub/rules.tcl`):** `every`/`cron` callbacks with `try-rule NAME { ... }`. Reads/writes global vars (also msg topics). 300s pump-off hysteresis. Tank range: on ≤101.5, off >102.5. Leak detection at 30 GPM rolling 10.5m window.

## Packages

All `jbr::*` packages live at `~/lib/tcl8/site-tcl` — cloned from separate git repos by `bootstrap.sh`, NOT in this repo. Key ones: `jbr::msg` (message bus), `jbr::cron`, `jbr::seconds` (relative time parsing), `jbr::unix`, `jbr::template` (SQL templating).

## Tests

```bash
tclsh hub/rules.test          # mock-based rules tests (tcltest)
pytest los/test_los.py        # RF link budget unit tests (pytest, mocks elevation fetching)
```

## RF Planning (`los/los.py`)

```bash
./los/los.py list
./los/los.py set "Place" antenna_height 6
./los/los.py analyze --sf 9                   # default: SF12, -148dBm sensitivity
./los/los.py analyze --fade-margin 20
./los/los.py --kml path/to/file.kml analyze   # default: ~/Downloads/TWP-LOS.kml
```

Elevation results cached in `los/elevation_cache.json` and `los/nlcd_cache.json` — delete to refresh.

## Client Hardware Drivers

`client/devices/MCP342x.tcl`, `ADS1115.tcl`, `gpio-{arch}.tcl`. GPIO driver auto-selects by `uname -m` (armv7l/aarch64). I2C via `piio` C extension at `pkg/piio/` (fossil clone).

## HTML Templates

`share/html/*.page` — server-side rendered via `jbr::template` / `jbr::template_macro`. Hot-reloaded on file change via `filewatch`. Auth via MD5 password file at `password` (format: `hash role username`).

## LoRa Redesign

`ARCHITECTURE-LORA.md` describes a phased migration from cellular/jbr::msg to LoRa mesh (Heltec V4 + Meshtastic) with mosquitto MQTT. Phase 1 runs both in parallel; Phase 2 removes cell. Not yet implemented.

## Gotchas

- `share/config/hub.cfg` is a per-station dummy config, NOT the main hub config (that's `hub/hub.cfg` with `set WEB_PORT 7777`)
- `noted.cfg` and `state.cfg` in `hub/` are runtime-persisted state files — edit manually to reset notification timers
- GPIO output commands propagate via `msg_set WATER $name:request $value` → hub trace → client `msg_subscribe` → `set-state` → `$name write $value`
- Channel OO class in `share/lib/channel.tcl` with `zero`/`scale`/`min`/`max`/`precision` calibration; `dev-channel` subclass adds device I/O in `client/channel.tcl`
