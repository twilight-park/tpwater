# Design: tpwater-client.tcl Mesh Integration

**Date:** 2026-05-29  
**Status:** Approved

## Purpose

Add `jbr::mesh` as a parallel transport to the existing `jbr::msg` connection in
`tpwater-client.tcl`. Sensor readings are broadcast over the Meshtastic LoRa network
in addition to the existing cellular/MSG path. Incoming mesh packets set local Tcl
variables directly, firing existing traces to execute output commands — no hub mesh
side required.

## Scope

Client (`client/tpwater-client.tcl`) only. Hub is unchanged. No MQTT/mosquitto.
This is Phase 1 parallel operation: both transports run simultaneously so LoRa delivery
can be validated against the existing MSG stream.

## Changes to `client/tpwater-client.tcl`

### 1. `mesh-connect` proc

Opens `/dev/ttyACM0` via `mesh::open`, registering `mesh-recv` as the receive callback.
Logs success or failure. On failure (device absent, open error), returns without crashing
— a missing radio must never prevent sensor recording.

```tcl
proc mesh-connect {} {
    if { ![file exists /dev/ttyACM0] } return
    try {
        mesh::open /dev/ttyACM0 mesh-recv
        log mesh connected
    } on error e {
        log-error "mesh-connect: $e"
    }
}
```

### 2. `mesh-recv pkt` proc

Called by `jbr::mesh` for every received packet. Two cases:

**Disconnect event** (`{event disconnect}`): log it, schedule reconnect via
`after 30000 mesh-connect`.

**Data packet**: extract the payload text, split into words, treat as space-separated
`name value` pairs, and `set ::$name $value` for each pair. Setting the global variable
fires any registered Tcl traces — specifically the `msg_subscribe WATER $name:request`
traces that call `set-state`, which writes the GPIO output.

```tcl
proc mesh-recv { pkt } {
    if { [dict exists $pkt event] } {
        log-error "mesh disconnected"
        after 30000 mesh-connect
        return
    }
    set text [encoding convertfrom utf-8 [dict get $pkt payload]]
    foreach { name value } $text {
        catch { set ::$name $value }
    }
}
```

### 3. `record` proc — add mesh send

After the existing `msg_cmd WATER "rec ..."` call, also broadcast the same string over
mesh. Wrapped in `catch` so a dead serial port never interrupts recording.

```tcl
try { mesh::send_text 0xFFFFFFFF "rec [clock seconds] $values"
} on error e { log-error "mesh send: $e" }
```

### 4. `sim-status` proc — add mesh send

Same pattern: mirror `"radio [clock seconds] $values"` to mesh alongside `msg_cmd`.

```tcl
try { mesh::send_text 0xFFFFFFFF "radio [clock seconds] $values"
} on error e { log-error "mesh send: $e" }
```

### 5. Main body — call `mesh-connect`

After the existing `readout` call and before `wapp-start`, add:

```tcl
mesh-connect
```

No guard needed — `mesh-connect` already checks for `/dev/ttyACM0` internally.

### 6. Package require

Add `package require jbr::mesh` near the top alongside the other `package require` calls.

## Message Formats

### Outbound (Pi → mesh → future hub)

| Proc | Text sent |
|------|-----------|
| `record` | `rec <unix_seconds> <val1> <val2> ...` |
| `sim-status` | `radio <unix_seconds> <val1> <val2> ...` |

Identical to the payload currently sent via `msg_cmd WATER`.
Broadcast address: `0xFFFFFFFF`.

### Inbound (mesh → Pi)

Space-separated `name value` pairs. Each pair maps directly to a Tcl global variable:

| Incoming text | Effect |
|--------------|--------|
| `pump:request 1` | `set ::pump:request 1` → fires `set-state pump` trace → writes GPIO |
| `golf:request 0` | `set ::golf:request 0` → fires `set-state golf` trace → writes GPIO |
| `clk 1716996200` | `set ::clk 1716996200` → fires `setdate` trace |

## Error Handling

- `mesh-connect` failure: logged, returns silently. Recording continues via `jbr::msg`.
- `mesh::send_text` failure: caught, logged. Recording continues.
- Mesh disconnect (EOF): logged, 30s reconnect scheduled via `after`.
- Malformed inbound packet: `catch` around `set ::$name $value` absorbs errors.

## Not in Scope

- Hub-side mesh receive
- MQTT / mosquitto integration
- Sending station name in outbound packets (hub has no mesh receiver)
- Output command filtering by station name (single station per Pi, no ambiguity)
