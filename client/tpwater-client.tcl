#!/usr/bin/env tclsh
#
set script_dir [file dirname $argv0]

set env(WATER) data.rkroll.com:8001

set HOME $env(HOME)
set TPWATER $HOME/tpwater

set HUB false

lappend auto_path $HOME/lib/tcl8/lib 
lappend auto_path /usr/share/tcltk/tcllib1.20
::tcl::tm::path add $HOME/lib/tcl8/site-tcl

package require coroutine::auto

package require jbr::msg
package require jbr::func
package require jbr::unix
package require jbr::with
package require jbr::seconds
package require jbr::mesh

set LOGPATH $::script_dir/../log
set LOGTAIL [file rootname [file tail $::argv0]]

source $script_dir/../share/lib/log.tcl
source $script_dir/../share/lib/codec-lib.tcl
source $script_dir/../share/lib/passwd-reader.tcl
source $script_dir/../share/lib/stacktrace.tcl
source $script_dir/http-service.tcl

source $script_dir/devices/ADS1115.tcl
source $script_dir/devices/MCP342x.tcl
source $script_dir/devices/gpio-[run uname -m].tcl

source $script_dir/sim-status.tcl
source $script_dir/channel.tcl

proc config-reader { dir apikey } {
    set ::names {}
    set ::config {}
    set ::outputs {}

    foreach config [glob -directory $dir -tails *.cfg] {
        lappend configs $config

        print $config
        set configuration [cat $dir/$config]
        print $configuration
        print

        foreach { name params } $configuration {
            if { [string index $name 0] eq "#" } { continue }
            if { $name eq "apikey" } { 
                if { $apikey == $params } {
                    set ::config $config
                }
                continue 
            }
            if { $name eq "record" } {
                set ::record $params
                continue
            }
            lappend ::names $name

            # This config is NOT for this card
            #
            if { $config ne $::config } { 
                msg_subscribe WATER $name   ; # subscribe to all the names in the system
                continue 
            }

            # This config is for this card
            #
            dict with params {
                switch $device {
                  ADS1115 -
                  MCP342x {

                    set dev $device:$bus:$address
                    if { [info command $dev] eq "" } {
                        ::i2c::${device}::a2d create $dev $bus $address
                    }
                    dict lappend ::$dev channels $name $channel
                    dict set ::$dev sample $sample

                    lappend ::inputs $name
                    lappend ::devices $dev

                    dev-channel create $name $dev $channel $sample
                  }
                  gpio {
                    set dev gpio
                    if { [info command $dev] eq "" } {
                        gpio::gpio::gpio create $dev 
                    }
                    dict lappend ::$dev channels $name $channel
                    dict set ::$dev sample 0

                    lappend ::inputs $name
                    lappend ::devices $dev

                    $dev function $channel $mode
                    dev-channel create $name $dev $channel 0
                  }
                }

                if { $mode eq "output" } { 
                    set value [$name read]

                    msg_set WATER $name:request $value {} sync
                    msg_set WATER $name         $value {} sync
                    msg_subscribe WATER $name:request {} "set-state $name" 
                    lappend ::outputs $name
                }
            }
            $name config $params
        }
        print
    }
    set ::devices [lsort -uniq $::devices]

    return $configs
}

proc set-state { name var args } {
    upvar $var value
    $name write $value
    set ::$name $value
    try { msg_set WATER $name $value {} async } on error e { print $::errorInfo }
}

proc avg { l } {
    return [expr { [sum $l] / double([llength $l]) }]
}

proc _sample { device args } {
    foreach { name chan } $args {
        $name sample [$device read $chan]
    }
}

proc sample { device args } {
    [coroutine::util create apply {{device args} {
        yield [info coroutine]
        _sample $device {*}$args
    }} $device {*}$args]
}

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

        mesh-send "rec [clock seconds] $values"
    } on error e { log-error record : $e }
}

proc readout {} {
    foreach device $::devices {
        _sample $device {*}[dict get [set ::$device] channels]
    }
    foreach device $::devices {
        set sample [dict get [set ::$device] sample]
        if { $sample } {
            every $sample "sample $device {*}[dict get [set ::$device] channels]"
        }
    }
    every [dict get $::record period] "record {*}$::inputs"
}

proc run { args } {
    with [open "| $args"] as p {
        return [lindex [read $p] 0]
    }
}

# Mesh (LoRa) transport is optional. ::mesh_enabled is set true only while a
# radio is open. If no radio is present at startup (after a few retries to
# cover boot-time USB enumeration) the mesh code is left disabled and all
# mesh sends become no-ops — a station with no radio runs purely on jbr::msg.
set ::mesh_enabled 0
set ::mesh_tries   0

proc mesh-connect {} {
    # Resolve the radio via stable /dev/serial/by-id symlink, resilient to
    # /dev/ttyACMx renumbering across reboots and re-plugs.
    set dev [mesh::find_device]
    if { $dev eq "" } {
        incr ::mesh_tries
        if { $::mesh_tries <= 5 } {
            after 30000 mesh-connect
        } else {
            log "no mesh radio found after $::mesh_tries tries — mesh disabled"
        }
        return
    }
    mesh::close
    try {
        mesh::open $dev mesh-recv
        set ::mesh_enabled 1
        set ::mesh_tries   0
        log mesh connected on $dev
    } on error e {
        log-error "mesh-connect: $e"
        set ::mesh_enabled 0
        after 30000 mesh-connect
    }
}

# Broadcast a text payload over mesh, if a radio is connected.
proc mesh-send { text } {
    if { !$::mesh_enabled } return
    try {
        mesh::send_text 0xFFFFFFFF $text
    } on error e {
        log-error "mesh send: $e"
        set ::mesh_enabled 0
        after 30000 mesh-connect
    }
}

proc mesh-recv { pkt } {
    if { [dict exists $pkt event] } {
        log-error "mesh disconnected"
        set ::mesh_enabled 0
        after 30000 mesh-connect
        return
    }
    # Only TEXT_MESSAGE_APP (portnum 1) carries our name/value payloads. Skip
    # telemetry/position/nodeinfo and other nodes' broadcasts.
    if { [dict get $pkt portnum] != 1 } return
    try {
        set text [encoding convertfrom utf-8 [dict get $pkt payload]]
        if { $text eq "" } return
        if { [llength $text] % 2 != 0 } {
            log-error "mesh-recv: odd-length payload, discarding"
            return
        }
        set allowed [list clk {*}[lmap n $::outputs { string cat $n :request }]]
        foreach { name value } $text {
            if { $name ni $allowed } continue
            catch { set ::$name $value }
        }
    } on error e {
        log-error "mesh-recv: $e"
    }
}

set apikey [cat $HOME/apikey]

passwd-reader $::script_dir/../password

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


msg_client WATER
msg_apikey WATER $apikey
msg_setreopen WATER 10000
msg_keepalive WATER 10000 120000 setstate

proc setdate { var args } {
    upvar $var value
    print exec sudo date -s @$value
}
msg_subscribe WATER clk {} setdate  [expr -60*60*24]

set configs [config-reader $::script_dir/../share/config $apikey]

readout
mesh-connect

proc sim-status {} {
    try {
        set values [get-sim-status]
        log sim status {*}$values
        msg_cmd WATER "radio [clock seconds] $values" 0 nowait

        mesh-send "radio [clock seconds] $values"
    } on error e {
        log-error $e
    }
}

if { [file exists /dev/ttyUSB2] } {
    every [expr 60000*10] sim-status
}

set WEB_PORT 7777
wapp-start [list -server $WEB_PORT -nowait]

vwait forever
