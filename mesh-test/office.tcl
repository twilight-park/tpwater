#!/usr/bin/env tclsh
# office.tcl — test observer node: jbr::msg client + mesh receiver
# Receives sensor broadcasts from listener over mesh.
# Relays hub commands (pump:request) out over mesh to listener.
#
# Usage: tclsh office.tcl <hub-ip>
# Example: tclsh office.tcl 192.168.1.10

set HOME $env(HOME)
lappend auto_path $HOME/lib/tcl8/lib
::tcl::tm::path add $HOME/lib/tcl8/site-tcl

package require jbr::msg
package require jbr::mesh

set HUBIP [lindex $argv 0]
if { $HUBIP eq "" } { puts "Usage: tclsh office.tcl <hub-ip>"; exit 1 }
set env(WATER) $HUBIP:8001

# --- msg: subscribe to hub commands and relay them over mesh ---
msg_client WATER
msg_setreopen WATER 5000

msg_subscribe WATER pump:request {} { apply {{var args} {
    upvar $var v
    puts "\[MSG→MESH\] relaying pump:request=$v over mesh"
    catch { mesh::send_text 0xFFFFFFFF "pump:request $v" }
}}}

msg_subscribe WATER tank {} { apply {{var args} {
    upvar $var v
    puts "\[MSG\] hub published tank=$v"
}}}

# --- mesh recv: receives sensor data from listener ---
proc mesh-recv { pkt } {
    if { [dict exists $pkt event] } {
        puts "\[MESH\] disconnected — retry in 10s"
        after 10000 mesh-connect
        return
    }
    set text [encoding convertfrom utf-8 [dict get $pkt payload]]
    puts "\[MESH RECV\] $text"
    if { [lindex $text 0] eq "rec" && [llength $text] >= 3 } {
        puts "\[SENSOR\] ts=[lindex $text 1] tank=[lindex $text 2] flow=[lindex $text 3]"
    }
}

proc mesh-connect {} {
    if { ![file exists /dev/ttyACM0] } {
        puts "\[MESH\] no /dev/ttyACM0 — retry in 10s"; after 10000 mesh-connect; return
    }
    mesh::close
    try {
        mesh::open /dev/ttyACM0 mesh-recv
        puts "\[MESH\] connected"
    } on error e {
        puts "\[MESH\] failed: $e — retry in 10s"; after 10000 mesh-connect
    }
}

mesh-connect

puts "office ready — hub=$HUBIP"
puts "  MSG:  subscribes to pump:request (relays to mesh) + tank"
puts "  MESH: receives rec from listener"
vwait forever
