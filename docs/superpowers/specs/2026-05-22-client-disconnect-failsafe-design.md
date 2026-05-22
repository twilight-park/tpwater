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
hub-side output zeroing when a client goes late.

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

**`config-reader`:** Inside the `if { [$name get mode] eq "output" }` block, add:

```tcl
dict lappend ::$configName outputs $name
```

This records which outputs belong to each config. Configs with no outputs (e.g.
waterplant) simply won't have the `outputs` key.

**`check` proc:** After marking a config late and resetting sensor values to `???`,
zero each of that config's outputs on the hub:

```tcl
if { [dict exists [set ::$config] outputs] } {
    foreach name [dict get [set ::$config] outputs] {
        log "Failsafe: zeroing $name:request (client $config late)"
        set ::$name:request 0
    }
}
```

This clears the hub's request state so the switch won't re-energize on reconnect.

## Timeout

60 seconds — unchanged from the existing lateness detection threshold. No new timers.

## Affected Configs

Only configs with `mode output` channels are affected:
- `golfcourse.cfg` — `golf` output
- `thirdlevel.cfg` — `thrd` output

`waterplant.cfg` has no outputs and is unaffected.

## Non-Goals

- No SMS notification when failsafe fires
- No change to the 60s timeout threshold
- No change to reconnect behavior (client reconnects normally; rules re-evaluate and
  may re-enable outputs if conditions warrant)
