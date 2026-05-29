#!/usr/bin/env tclsh
# hub.tcl — minimal test msg hub with a couple of published values
# Run on the dev machine (or any machine reachable by both Pis).
# Usage: tclsh hub.tcl [port]
#   Default port: 8001

set HOME $env(HOME)
lappend auto_path $HOME/lib/tcl8/lib
::tcl::tm::path add $HOME/lib/tcl8/site-tcl

package require jbr::msg

set PORT [lindex $argv 0]
if { $PORT eq "" } { set PORT 8001 }

# msg_server reads its listen address from $env(WATER) as host:port.
# Empty host binds all interfaces.
set env(WATER) ":$PORT"
msg_server WATER

# Permit all client hosts (default deny would reject everyone).
msg_allow WATER *

# Publish variables — sets up the write-trace that pushes to subscribers.
# Setting the published global then propagates to all subscribed clients.
msg_publish WATER tank
msg_publish WATER clk
msg_publish WATER pump:request
msg_publish WATER golf:request

set ::pump:request 0
set ::golf:request 0
set ::tank 0.0

# Update published vars; the publish traces push them to subscribers.
proc tick {} {
    set ::tank [format %.2f [expr { 50.0 + sin([clock seconds] * 0.05) * 30.0 }]]
    set ::clk  [clock seconds]
    puts "HUB tick: tank=$::tank clk=$::clk pump:request=[set ::pump:request]"
    after 10000 tick
}

proc toggle-pump {} {
    set ::pump:request [expr { 1 - [set ::pump:request] }]
    puts "HUB toggled pump:request => [set ::pump:request]"
    after 30000 toggle-pump
}

# Open the listening socket (msg_server only sets up the interp).
msg_up WATER

puts "Hub listening on port $PORT"
puts "Publishes: tank (sine wave), clk, pump:request (toggles every 30s)"
after 2000 tick
after 15000 toggle-pump

vwait forever
