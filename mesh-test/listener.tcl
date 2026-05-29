#!/usr/bin/env tclsh
# listener.tcl — test field node: jbr::msg client + jbr::mesh bridge
# Mirrors the tpwater-client pattern: subscribes to hub vars, forwards
# commands from mesh to local traces, sends sensor readings over mesh.
#
# Usage: tclsh listener.tcl <hub-ip>
# Example: tclsh listener.tcl 192.168.1.10

set HOME $env(HOME)
lappend auto_path $HOME/lib/tcl8/lib
::tcl::tm::path add $HOME/lib/tcl8/site-tcl

package require jbr::msg
package require jbr::mesh

set HUBIP  [lindex $argv 0]
set DEVICE [lindex $argv 1]
if { $DEVICE eq "" } { set DEVICE /dev/ttyACM0 }
if { $HUBIP eq "" } { puts "Usage: tclsh listener.tcl <hub-ip> ?/dev/ttyACMx?"; exit 1 }
set env(WATER) $HUBIP:8001

# --- Simulated outputs (mirrors tpwater-client) ---
set ::pump:request 0
set ::golf:request 0

proc set-state { name var args } {
    upvar $var value
    puts "\[TRACE\] $name => $value  (would write GPIO)"
}

# --- msg subscriptions ---
msg_client WATER
msg_setreopen WATER 5000

msg_subscribe WATER pump:request {} "set-state pump"
msg_subscribe WATER golf:request {} "set-state golf"
msg_subscribe WATER clk {} { apply {{var args} {
    upvar $var v
    puts "\[MSG\] clk = $v"
}}}

# --- mesh recv: incoming mesh → set local vars (fires traces) ---
proc mesh-recv { pkt } {
    if { [dict exists $pkt event] } {
        puts "\[MESH\] disconnected — retrying in 10s"
        after 10000 mesh-connect
        return
    }
    # Only TEXT_MESSAGE_APP (portnum 1) carries our payloads; skip config/
    # telemetry/nodeinfo noise from the want_config dump.
    if { [dict get $pkt portnum] != 1 } return
    set text [encoding convertfrom utf-8 [dict get $pkt payload]]
    if { $text eq "" } return
    puts "\[MESH RECV\] from=[format %x [dict get $pkt from]] rssi=[dict get $pkt rssi] snr=[dict get $pkt snr]: $text"
    if { [llength $text] % 2 != 0 } { puts "\[MESH\] odd payload, skip"; return }
    set allowed [list pump:request golf:request clk]
    foreach { name value } $text {
        if { $name ni $allowed } { puts "\[MESH\] unknown: $name"; continue }
        set ::$name $value
    }
}

proc mesh-connect {} {
    set dev [mesh::find_device $::DEVICE]
    if { $dev eq "" } {
        puts "\[MESH\] no radio device found — retry in 10s"; after 10000 mesh-connect; return
    }
    mesh::close
    try {
        mesh::open $dev mesh-recv
        puts "\[MESH\] connected on $dev"
    } on error e {
        puts "\[MESH\] failed: $e — retry in 10s"; after 10000 mesh-connect
    }
}

# --- Periodic sensor send over mesh (mirrors record proc) ---
set ::seq 0
proc send-reading {} {
    incr ::seq
    set ts   [clock seconds]
    set tank [format %.2f [expr { 50.0 + sin($::seq * 0.5) * 30.0 }]]
    set flow [format %.2f [expr { 10.0 + $::seq % 5 }]]
    set msg  "rec $ts $tank $flow"
    puts "\[SEND\] $msg"
    catch { mesh::send_text 0xFFFFFFFF $msg } e
    after 10000 send-reading
}

mesh-connect
after 3000 send-reading

puts "listener ready — hub=$HUBIP"
puts "  MSG:  subscribes to pump:request golf:request clk"
puts "  MESH: sends rec every 10s; accepts pump:request golf:request"
vwait forever
