# Client Disconnect Failsafe Design

**Date:** 2026-05-22  
**Status:** Approved

## Problem

If a client Pi controlling a switch (GPIO output) loses network connectivity, the switch
stays in whatever state it was last commanded to. The hub's `:request` variable also
retains the last value, so when the client reconnects it re-energizes the switch
immediately. There is no automatic shutoff.

## Solution

Option C — belt and suspenders: fix the existing (broken) client-side failsafe and add
hub-side output zeroing on a separate failsafe timeout.

## Changes

### 1. Client-side (`client/tpwater-client.tcl`)

Fix two typos in the `setstate` proc (lines ~190–199):

- `foreach $name $::outputs` → `foreach name $::outputs`  
  (`$name` as a loop variable declaration is wrong Tcl — it dereferences `name` instead
  of binding it)
- `print set ::$value 0` → `print set ::$name 0`

The surrounding infrastructure is already correct: `msg_keepalive WATER 5000 60000 setstate`
sends keepalives every 5s and calls `setstate` with connection state when the 60s timeout
fires. Once the proc is fixed, any client output is written to 0 within 60s of losing
the hub.

### 2. Hub-side (`hub/tpwater-hub.tcl`)

Two separate thresholds, both checked in the `check` proc:

**Lateness (60s) — unchanged:** marks `$config:late true` and resets sensor values to `???`.

**Failsafe (180s) — new:** zeros each output's `:request` on the hub. Fires once per
disconnect (guarded by a `$config:failsafe` flag, reset to `false` when packets resume).

**`config-reader`:** Track per-config outputs and initialize the failsafe flag:

```tcl
# inside if { [$name get mode] eq "output" }:
dict lappend ::$configName outputs $name

# in the second loop initializing per-config state:
set ::$config:failsafe false
```

**`check` proc additions:**

```tcl
# existing lateness block (delta > 60) — unchanged
if { !$late && $delta > 60 } {
    log "Packet late $delta seconds at $now"
    set ::$config:late true
    set names [dict get [set ::$config] names]
    foreach name $names {
        set ::$name "???"
    }
}

# new failsafe block (delta > 180, fires once)
set failsafe [set ::$config:failsafe]
if { !$failsafe && $delta > 180 } {
    set ::$config:failsafe true
    if { [dict exists [set ::$config] outputs] } {
        foreach name [dict get [set ::$config] outputs] {
            log "Failsafe: zeroing $name:request (client $config offline ${delta}s)"
            set ::$name:request 0
        }
    }
}
```

**Reset on reconnect:** In the `rec` handler, after `set ::$config:late false`, also
reset `set ::$config:failsafe false`.

## Thresholds

| Event           | Threshold | Variable        |
|-----------------|-----------|-----------------|
| Mark late       | 60s       | `$config:late`  |
| Zero outputs    | 180s      | `$config:failsafe` |

## Affected Configs

Only configs with `mode output` channels are affected:
- `golfcourse.cfg` — `golf` output
- `thirdlevel.cfg` — `thrd` output

`waterplant.cfg` has no outputs and is unaffected.

## Non-Goals

- No SMS notification when failsafe fires
- No change to reconnect behavior (client reconnects normally; rules re-evaluate and
  may re-enable outputs if conditions warrant)
