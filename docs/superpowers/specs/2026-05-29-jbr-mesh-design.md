# Design: `jbr::mesh` Tcl Package

**Date:** 2026-05-29  
**Status:** Approved

## Purpose

Provide a critcl-built Tcl package (`jbr::mesh`) that lets a Raspberry Pi talk
directly to a co-located Meshtastic node over USB serial — encoding/sending sensor
readings and decoding/receiving output commands — without any MQTT broker or Python
sidecar. This is Phase 1 of the TPWater LoRa migration (parallel operation alongside
`jbr::msg`).

## Package Location

```
~/src/jbr.tcl/mesh/
  mesh.tcl              # critcl package — package provide jbr::mesh 1.0
  Makefile              # critcl -pkg mesh.tcl  →  lib/
  nanopb/               # vendored nanopb runtime (pb.h, pb_encode.h, pb_decode.h,
                        #   pb.c, pb_encode.c, pb_decode.c)
  proto/                # pre-generated nanopb C from Meshtastic .proto files
    mesh.pb.h / mesh.pb.c
    portnums.pb.h / portnums.pb.c
    telemetry.pb.h / telemetry.pb.c
```

The `proto/` generated files are committed — no `protoc` required on the Pi.
Regeneration is a dev-machine task when Meshtastic proto definitions change.

## Layer Split

### C layer (critcl `ccode` / `cproc`)

Handles only protobuf encode/decode and StreamAPI framing:

- `mesh::encode_packet to_node port_num payload_bytes` → binary frame  
  Frame format: `0x94 0xc3 len_hi len_lo <nanopb-encoded ToRadio>`
- `mesh::decode_frame binary_data` → Tcl dict  
  Dict keys: `portnum from to payload rssi snr`

C sources included via `critcl::csources` and `critcl::cheaders`:
- nanopb runtime (`pb.c`, `pb_encode.c`, `pb_decode.c`)
- Meshtastic generated stubs (`mesh.pb.c`, `portnums.pb.c`, `telemetry.pb.c`)

### Tcl layer

Handles serial I/O, framing state machine, and event dispatch:

- Opens device with `fconfigure -mode 115200,n,8,1 -translation binary -buffering full`
- `fileevent` readable handler accumulates raw bytes into a namespace buffer
- 4-state framing machine: `SYNC1 → SYNC2 → LEN → DATA`
  - Wait for `0x94`, then `0xc3`, read 2-byte big-endian length, accumulate payload
  - A corrupt byte resets to `SYNC1`
  - On complete frame: call `mesh::decode_frame`, dispatch to callback
- Callback receives decoded dict; `{event disconnect}` on EOF

## Public API

```tcl
mesh::open device ?callback?     ;# open serial port; optional receive callback
mesh::close                      ;# close serial port, clean up
mesh::send_text  to_node text    ;# encode TEXT_MESSAGE_APP (portnum 1) and write
mesh::send_data  to_node portnum bytes  ;# raw portnum + payload bytes
mesh::on_receive script          ;# set/replace receive callback
```

`to_node` is a 32-bit integer node ID. Broadcast = `0xFFFFFFFF`.

Callback invocation: `script $packet_dict`

## Error Handling

- `mesh::open` raises on device not present; caller retries with `after`.
- EOF on the channel: dispatch `{event disconnect}`, close and clean up.
- No automatic reconnect inside the package — consistent with `jbr::msg` pattern
  where reconnect policy lives in the caller (`msg_setreopen`).

## Build and Install

```makefile
# mesh/Makefile
CRITCL = /home/john/bin/critcl

all:
	$(CRITCL) -pkg mesh.tcl

install:
	cp -r lib/mesh ~/lib/tcl8/site-tcl/jbr/
```

After install: `package require jbr::mesh` works from any Tcl script that has
`~/lib/tcl8/site-tcl` on its module path.

## Meshtastic Serial Protocol (StreamAPI)

- Baud: 115200, 8N1
- Frame: `[0x94][0xc3][len_MSB][len_LSB][protobuf_payload]`
- Host→device: `ToRadio` protobuf (wraps `MeshPacket`)
- Device→host: `FromRadio` protobuf (delivers `MeshPacket`, config, node info)
- On open: send `WantConfigId` `ToRadio` to trigger radio to announce its node ID

## Proto Files

Minimum required Meshtastic proto files:

| Proto | Contents used |
|-------|--------------|
| `mesh.proto` | `MeshPacket`, `ToRadio`, `FromRadio`, `Data` |
| `portnums.proto` | `PortNum` enum (`TEXT_MESSAGE_APP = 1`) |
| `telemetry.proto` | `Telemetry` (optional, for typed sensor payloads) |

Source: `github.com/meshtastic/protobufs` — generate with  
`python3 -m grpc_tools.protoc --nanopb_out=proto/ mesh.proto portnums.proto telemetry.proto`

## Out of Scope

- Hub-side MQTT integration (separate design)
- tpwater-client.tcl wiring (follow-on after package is built and tested)
- Automatic reconnect logic (caller responsibility)
- Sending `WantConfigId` handshake at open time (Phase 2; not needed to send packets)
