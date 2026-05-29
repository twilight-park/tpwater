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

msg_server WATER $PORT

# Publish initial state
set ::pump:request 0
set ::golf:request 0
set ::tank 0.0

# Flip pump:request every 30s so Pis can see commanded changes arrive
proc tick {} {
    set ::tank   [format %.2f [expr { 50.0 + sin([clock seconds] * 0.05) * 30.0 }]]
    set ::clk    [clock seconds]
    msg_set WATER tank          $::tank        {} sync
    msg_set WATER clk           $::clk         {} sync
    puts "HUB tick: tank=$::tank clk=$::clk pump:request=[set ::pump:request]"
    after 10000 tick
}

proc toggle-pump {} {
    set ::pump:request [expr { 1 - [set ::pump:request] }]
    msg_set WATER pump:request  [set ::pump:request] {} sync
    puts "HUB toggled pump:request => [set ::pump:request]"
    after 30000 toggle-pump
}

puts "Hub listening on port $PORT"
puts "Publishes: tank (sine wave), clk, pump:request (toggles every 30s)"
after 2000 tick
after 15000 toggle-pump

vwait forever
