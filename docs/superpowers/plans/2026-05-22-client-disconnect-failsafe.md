# Client Disconnect Failsafe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically turn off GPIO output switches when a client Pi loses network connectivity, and clear the hub's `:request` state so switches don't re-energize on reconnect.

**Architecture:** Two-part fix. The client already has a disconnect callback (`setstate`) wired to the keepalive timer but it has two typos that make it a no-op — fix those. The hub gains a 180s failsafe threshold in the `check` proc (separate from the existing 60s lateness threshold) that zeros `:request` for any outputs owned by a late client; a `$config:failsafe` flag prevents repeat firing.

**Tech Stack:** Tcl 8.6, `jbr::msg` message bus, GPIO via `gpio` device, SQLite (not touched here)

---

## File Map

| File | Change |
|------|--------|
| `client/tpwater-client.tcl` | Fix two typos in `setstate` proc (lines 194, 197) |
| `hub/tpwater-hub.tcl` | `config-reader`: track per-config outputs + init failsafe flag |
| `hub/tpwater-hub.tcl` | `check` proc: add 180s failsafe block |
| `hub/tpwater-hub.tcl` | `rec` handler: reset `$config:failsafe` on reconnect |

---

### Task 1: Fix client-side `setstate` proc

**Files:**
- Modify: `client/tpwater-client.tcl:190-199`

The proc is called by `msg_keepalive` when the connection to the hub changes state. It
has two bugs: `foreach $name` uses a dollar sign on the loop variable (Tcl binds the loop
variable by name, not value — `$name` dereferences whatever `name` currently holds instead
of iterating), and `print set ::$value 0` references an undefined variable `value`.

- [ ] **Step 1: Open `client/tpwater-client.tcl` and locate the `setstate` proc (~line 190)**

The current (broken) code looks like:
```tcl
proc setstate { server sock id op } {
    upvar #0 $server S
    print SETSTATE $server $id -> $S(connection)
    if { $S(connection) ne "Up" } {
        foreach $name $::outputs {
            $name write 0
            set ::$name 0
            print set ::$value 0
        }
    }
}
```

- [ ] **Step 2: Replace with the fixed version**

```tcl
proc setstate { server sock id op } {
    upvar #0 $server S
    print SETSTATE $server $id -> $S(connection)
    if { $S(connection) ne "Up" } {
        foreach name $::outputs {
            $name write 0
            set ::$name 0
            print set ::$name 0
        }
    }
}
```

Changes: `foreach $name` → `foreach name`, `::$value` → `::$name`.

- [ ] **Step 3: Verify the diff looks right**

```bash
cd /home/john/src/tpwater
git diff client/tpwater-client.tcl
```

Expected: two changed lines — the `foreach` line and the `print` line. No other changes.

- [ ] **Step 4: Commit**

```bash
git add client/tpwater-client.tcl
git commit -m "fix: correct setstate proc so client turns off outputs on disconnect"
```

---

### Task 2: Track per-config outputs in hub `config-reader`

**Files:**
- Modify: `hub/tpwater-hub.tcl:51-97` (`config-reader` proc)

The hub needs to know which outputs belong to which config so the `check` proc can zero
them. Currently `::outputs` is a flat global list with no per-config breakdown. We add
`dict lappend ::$configName outputs $name` inside the existing output block, and initialize
a `$config:failsafe` flag in the second loop that sets up per-config state.

- [ ] **Step 1: In `config-reader`, find the output registration block (~line 81)**

Current code inside `foreach { name params } $configuration`:
```tcl
if { [$name get mode] eq "output" } {
    msg_publish WATER $name:request 
    if { $config eq "hub.cfg" } {
        trace add variable ::$name:request write "set-state $name"
    }
    lappend ::outputs $name
}
```

- [ ] **Step 2: Add per-config output tracking**

```tcl
if { [$name get mode] eq "output" } {
    msg_publish WATER $name:request 
    if { $config eq "hub.cfg" } {
        trace add variable ::$name:request write "set-state $name"
    }
    lappend ::outputs $name
    dict lappend ::$configName outputs $name
}
```

Added one line: `dict lappend ::$configName outputs $name`.

- [ ] **Step 3: Find the second loop that initializes per-config state (~line 91)**

Current code:
```tcl
foreach config $configs {
    set ::$config:last 0
    set ::$config:late true
}
```

- [ ] **Step 4: Add failsafe flag initialization**

```tcl
foreach config $configs {
    set ::$config:last 0
    set ::$config:late true
    set ::$config:failsafe false
}
```

Added one line: `set ::$config:failsafe false`.

- [ ] **Step 5: Verify the diff**

```bash
git diff hub/tpwater-hub.tcl
```

Expected: two added lines — one inside the output `if` block, one in the second `foreach` loop.

- [ ] **Step 6: Commit**

```bash
git add hub/tpwater-hub.tcl
git commit -m "feat: track per-config outputs and init failsafe flag in config-reader"
```

---

### Task 3: Add 180s failsafe block to hub `check` proc

**Files:**
- Modify: `hub/tpwater-hub.tcl:160-175` (`check` proc)

The `check` proc runs every 1000ms per config. It already handles the 60s lateness case.
We add a second block that fires once (guarded by `$config:failsafe`) when `delta > 180`,
zeroing each output's `:request` variable on the hub.

- [ ] **Step 1: Locate the `check` proc (~line 160)**

Current code:
```tcl
proc check { config } {
    set now [clock seconds]
    set last [set ::$config:last]
    set late [set ::$config:late]

    set delta [expr { abs($now - $last) }]
    if { !$late && $delta > 60 } {
        log "Packet late $delta seconds at $now"
        set ::$config:late true
        set names  [dict get [set ::$config] names]
        foreach name $names {
            print set ::$name "???"
            set ::$name "???"
        }
    }
}
```

- [ ] **Step 2: Replace with the version that adds the failsafe block**

```tcl
proc check { config } {
    set now [clock seconds]
    set last [set ::$config:last]
    set late [set ::$config:late]

    set delta [expr { abs($now - $last) }]
    if { !$late && $delta > 60 } {
        log "Packet late $delta seconds at $now"
        set ::$config:late true
        set names  [dict get [set ::$config] names]
        foreach name $names {
            print set ::$name "???"
            set ::$name "???"
        }
    }

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
}
```

- [ ] **Step 3: Verify the diff**

```bash
git diff hub/tpwater-hub.tcl
```

Expected: the new `failsafe` block appended inside `check`, nothing else changed.

- [ ] **Step 4: Commit**

```bash
git add hub/tpwater-hub.tcl
git commit -m "feat: zero outputs after 180s client offline (hub-side failsafe)"
```

---

### Task 4: Reset failsafe flag on client reconnect

**Files:**
- Modify: `hub/tpwater-hub.tcl:121-158` (`rec` handler)

When a client sends a `rec` packet the hub already clears `$config:late`. We need to
also clear `$config:failsafe` so the failsafe arms again on the next disconnect.

- [ ] **Step 1: Locate the `rec` handler and find where `$config:late` is reset (~line 144)**

Current code (inside `msg_srvproc WATER rec`):
```tcl
set ::$config:late false
set ::$config:last $now
```

- [ ] **Step 2: Add the failsafe reset on the line after**

```tcl
set ::$config:late false
set ::$config:failsafe false
set ::$config:last $now
```

- [ ] **Step 3: Verify the diff**

```bash
git diff hub/tpwater-hub.tcl
```

Expected: one added line (`set ::$config:failsafe false`) next to the existing `late` reset.

- [ ] **Step 4: Commit**

```bash
git add hub/tpwater-hub.tcl
git commit -m "feat: reset failsafe flag when client reconnects"
```

---

## Manual Verification

The system runs on live hardware, so there's no automated test suite. Verify by:

1. **Start the hub** on `data.rkroll.com` and confirm a client (e.g. golfcourse) is connected and `golf:request` is 1 (or set it to 1 via `/press`).
2. **Disconnect the client** (stop the service, unplug ethernet, or block the port).
3. **After ~60s:** Confirm hub logs show "Packet late" and the sensor values show `???`.
4. **After ~180s:** Confirm hub logs show "Failsafe: zeroing golf:request" and that `golf:request` reads 0 via the `/clients` endpoint or hub log.
5. **Reconnect the client:** Confirm the hub logs show packet receipt and `golf:request` stays 0 until rules re-evaluate (tank level check in `rules.tcl`).
6. **Client-side:** On the Pi, stop the hub temporarily (or block the port from the Pi side). After ~60s the client's `setstate` should fire and log `SETSTATE ... -> Down`, and the GPIO output should read 0.
