# Client Mesh Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `jbr::mesh` as a parallel transport alongside `jbr::msg` in `tpwater-client.tcl` — sensor readings broadcast over LoRa mesh, incoming mesh packets execute commands via Tcl variable traces.

**Architecture:** Three procs added (`mesh-connect`, `mesh-recv`), two existing procs updated (`record`, `sim-status`), one `package require` and one `mesh-connect` call added to the main body. All changes are in a single file. The mesh transport is always optional — its failure never interrupts sensor recording.

**Tech Stack:** Tcl 8.6, `jbr::msg` (existing), `jbr::mesh` (critcl package at `~/lib/tcl8/lib/mesh/`)

---

## File Map

| File | Change |
|------|--------|
| `client/tpwater-client.tcl` | All changes — package require, two new procs, two proc updates, one main body call |

---

### Task 1: Add `package require jbr::mesh`

**Files:**
- Modify: `client/tpwater-client.tcl:16-22`

- [ ] **Step 1: Add the package require after the existing jbr:: requires**

Open `client/tpwater-client.tcl`. After line 22 (`package require jbr::seconds`), add one line:

```tcl
package require coroutine::auto

package require jbr::msg
package require jbr::func
package require jbr::unix
package require jbr::with
package require jbr::seconds
package require jbr::mesh
```

- [ ] **Step 2: Verify the file parses (syntax check)**

```bash
cd /home/john/src/tpwater
tclsh -c 'source client/tpwater-client.tcl' 2>&1 | head -5 || true
```

Expected: error about missing `apikey` or hardware (not a syntax error). Any `invalid command name` pointing to line 23 would indicate the package isn't installed — check `~/lib/tcl8/lib/mesh/pkgIndex.tcl` exists.

- [ ] **Step 3: Commit**

```bash
git add client/tpwater-client.tcl
git commit -m "feat: add package require jbr::mesh to tpwater-client"
```

---

### Task 2: Add `mesh-connect` proc

**Files:**
- Modify: `client/tpwater-client.tcl` — insert after `proc run { args }` block (after line 184)

- [ ] **Step 1: Insert `mesh-connect` proc after the `run` proc**

After the closing `}` of `proc run { args }` (line 184), insert:

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

- [ ] **Step 2: Verify the proc is defined after sourcing**

```bash
tclsh <<'EOF'
lappend auto_path $env(HOME)/lib/tcl8/lib
package require jbr::mesh
proc log args {}
proc log-error args {}
proc mesh-connect {} {
    if { ![file exists /dev/ttyACM0] } return
    try {
        mesh::open /dev/ttyACM0 mesh-recv
        log mesh connected
    } on error e {
        log-error "mesh-connect: $e"
    }
}
puts "proc defined: [info procs mesh-connect]"
# Test no-op when device absent
file delete -force /tmp/ttyACM0_test
mesh-connect
puts "mesh-connect with no device: OK (no crash)"
EOF
```

Expected:
```
proc defined: mesh-connect
mesh-connect with no device: OK (no crash)
```

- [ ] **Step 3: Commit**

```bash
git add client/tpwater-client.tcl
git commit -m "feat: add mesh-connect proc to tpwater-client"
```

---

### Task 3: Add `mesh-recv` proc

**Files:**
- Modify: `client/tpwater-client.tcl` — insert immediately after `mesh-connect` proc

- [ ] **Step 1: Insert `mesh-recv` proc after `mesh-connect`**

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

- [ ] **Step 2: Verify disconnect handling and variable-setting logic**

```bash
tclsh <<'EOF'
proc log-error args { puts "log-error: $args" }
proc mesh-connect {} { puts "mesh-connect called" }

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

# Test disconnect event
mesh-recv {event disconnect}
puts "disconnect: OK"

# Test variable setting
set ::pump:request 0
trace add variable ::pump:request write { apply { {n1 n2 op} {
    upvar $n1 v
    puts "trace fired: pump:request=$v"
}}}
mesh-recv [dict create payload [encoding convertto utf-8 "pump:request 1"]]
puts "pump:request is now: [set ::pump:request]"
EOF
```

Expected:
```
log-error: mesh disconnected
disconnect: OK
trace fired: pump:request=1
pump:request is now: 1
```

- [ ] **Step 3: Commit**

```bash
git add client/tpwater-client.tcl
git commit -m "feat: add mesh-recv proc to tpwater-client"
```

---

### Task 4: Update `record` proc to send over mesh

**Files:**
- Modify: `client/tpwater-client.tcl:151-165` (`record` proc)

- [ ] **Step 1: Add mesh send inside the existing `record` proc**

The current `record` proc (lines 151-165) looks like:

```tcl
proc record { args } {
    try {
        foreach name $args {
            set value [$name value]
            lappend values $value
            set ::$name [$name scaled $value]
        }
        log record [clock seconds] {*}[zip $args $values]

        try { msg_cmd WATER "rec [clock seconds] $values" 0 nowait 
        } on error e {
            log-error $e
        }
    } on error e { log-error record : $e }
}
```

Replace with:

```tcl
proc record { args } {
    try {
        foreach name $args {
            set value [$name value]
            lappend values $value
            set ::$name [$name scaled $value]
        }
        log record [clock seconds] {*}[zip $args $values]

        try { msg_cmd WATER "rec [clock seconds] $values" 0 nowait 
        } on error e {
            log-error $e
        }

        try { mesh::send_text 0xFFFFFFFF "rec [clock seconds] $values"
        } on error e { log-error "mesh send: $e" }
    } on error e { log-error record : $e }
}
```

- [ ] **Step 2: Verify the proc definition is syntactically valid**

```bash
tclsh <<'EOF'
lappend auto_path $env(HOME)/lib/tcl8/lib
package require jbr::mesh
namespace eval mesh {}
proc mesh::send_text {args} { puts "mesh::send_text called: $args" }
proc log args {}
proc log-error args {}
proc msg_cmd args {}
proc zip {a b} { set r {} ; foreach x $a y $b { lappend r $x $y } ; return $r }

proc record { args } {
    try {
        foreach name $args {
            set value [$name value]
            lappend values $value
            set ::$name [$name scaled $value]
        }
        log record [clock seconds] {*}[zip $args $values]

        try { msg_cmd WATER "rec [clock seconds] $values" 0 nowait 
        } on error e {
            log-error $e
        }

        try { mesh::send_text 0xFFFFFFFF "rec [clock seconds] $values"
        } on error e { log-error "mesh send: $e" }
    } on error e { log-error record : $e }
}

puts "record proc defined OK"
puts "mesh send_text stub works: [info procs mesh::send_text]"
EOF
```

Expected:
```
record proc defined OK
mesh send_text stub works: mesh::send_text
```

- [ ] **Step 3: Commit**

```bash
git add client/tpwater-client.tcl
git commit -m "feat: mirror sensor record to mesh in tpwater-client"
```

---

### Task 5: Update `sim-status` proc to send over mesh

**Files:**
- Modify: `client/tpwater-client.tcl:218-226` (`sim-status` proc)

- [ ] **Step 1: Add mesh send inside `sim-status`**

The current `sim-status` proc (lines 218-226) looks like:

```tcl
proc sim-status {} {
    try { 
        set values [get-sim-status]
        log sim status {*}$values
        msg_cmd WATER "radio [clock seconds] $values" 0 nowait 
    } on error e {
        log-error $e
    }
}
```

Replace with:

```tcl
proc sim-status {} {
    try { 
        set values [get-sim-status]
        log sim status {*}$values
        msg_cmd WATER "radio [clock seconds] $values" 0 nowait 

        try { mesh::send_text 0xFFFFFFFF "radio [clock seconds] $values"
        } on error e { log-error "mesh send: $e" }
    } on error e {
        log-error $e
    }
}
```

- [ ] **Step 2: Verify the proc definition**

```bash
tclsh <<'EOF'
proc mesh::send_text {args} { puts "mesh::send_text called" }
proc log args {}
proc log-error args {}
proc msg_cmd args {}
proc get-sim-status {} { return "42 55" }

proc sim-status {} {
    try { 
        set values [get-sim-status]
        log sim status {*}$values
        msg_cmd WATER "radio [clock seconds] $values" 0 nowait 

        try { mesh::send_text 0xFFFFFFFF "radio [clock seconds] $values"
        } on error e { log-error "mesh send: $e" }
    } on error e {
        log-error $e
    }
}

sim-status
puts "sim-status: OK"
EOF
```

Expected:
```
mesh::send_text called
sim-status: OK
```

- [ ] **Step 3: Commit**

```bash
git add client/tpwater-client.tcl
git commit -m "feat: mirror sim-status to mesh in tpwater-client"
```

---

### Task 6: Call `mesh-connect` in main body

**Files:**
- Modify: `client/tpwater-client.tcl` — insert after `readout` call (line 216)

- [ ] **Step 1: Insert `mesh-connect` call after `readout`**

After line 216 (`readout`), add:

```tcl
readout

mesh-connect
```

The full block around this insertion (lines 214-230) should look like:

```tcl
set configs [config-reader $::script_dir/../share/config $apikey]

readout

mesh-connect

proc sim-status {} {
```

- [ ] **Step 2: Verify ordering is correct**

```bash
grep -n 'readout\|mesh-connect\|wapp-start\|vwait' client/tpwater-client.tcl
```

Expected output (line numbers may shift slightly):
```
216:readout
218:mesh-connect
...
wapp-start
vwait forever
```

- [ ] **Step 3: Commit**

```bash
git add client/tpwater-client.tcl
git commit -m "feat: call mesh-connect in tpwater-client main body"
```

---

## Manual Verification

The system runs on live hardware. To verify without a Pi:

```bash
# Confirm all procs are defined and the file is syntactically self-consistent:
grep -n 'proc mesh-connect\|proc mesh-recv\|mesh::send_text\|mesh-connect\|package require jbr::mesh' \
    client/tpwater-client.tcl
```

Expected output:
```
23:package require jbr::mesh
185:proc mesh-connect {} {
193:proc mesh-recv { pkt } {
160:        try { msg_cmd WATER "rec [clock seconds] $values" 0 nowait
162:        try { mesh::send_text 0xFFFFFFFF "rec [clock seconds] $values"
224:        try { mesh::send_text 0xFFFFFFFF "radio [clock seconds] $values"
218:mesh-connect
```

On a Pi with the Meshtastic node connected:
1. Start the client: `./tpwater.sh start`
2. Tail the log: `./tpwater.sh tail`
3. Confirm log shows `mesh connected` within the first few lines
4. After one record interval (~20s), confirm log shows `record <seconds> <vals>` and no `mesh send:` errors
5. On another Meshtastic node, observe the broadcast text packet arriving
