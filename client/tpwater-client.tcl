#!/usr/bin/env tclsh
#

set env(WATER) data.rkroll.com:8001

set HOME $env(HOME)
set TPWATER $HOME/tpwater

lappend auto_path $HOME/lib/tcl8/lib 
lappend auto_path /usr/share/tcltk/tcllib1.20
::tcl::tm::path add $HOME/lib/tcl8/site-tcl

package require coroutine::auto

package require jbr::func
package require jbr::with
package require jbr::unix
package require jbr::msg

set script_dir [file dirname $argv0]

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
        set configName [file rootname [file tail $config]]
        lappend configs $configName

        set ::$configName:status ?
        msg_subscribe WATER $configName:status

        set ::$configName [cat $dir/$config]
        if { [dict get [set ::$configName] apikey] eq $apikey } { 
            set ::config $configName
        }
        print $configName [expr { $::config eq $configName ? "Local" : "Remote" }]
        print [set ::$configName]

        foreach { name params } [set ::$configName] {
            if { [string index $name 0] eq "#" } { continue }
            if { $name eq "apikey" } { continue }
            if { $name eq "record" } {
                set ::record $params
                continue
            }
            lappend ::names $name

            # This config if NOT for this card
            #
            if { $configName ne $::config } { 
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

                    channel create $name $name $dev $channel $sample
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
                    channel create $name $name $dev $channel 0
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

proc every {ms body} {
    after $ms [list after idle [namespace code [info level 0]]]
    try $body
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

set apikey [cat $HOME/apikey]

passwd-reader $::script_dir/../password


msg_client WATER
msg_apikey WATER $apikey
msg_setreopen WATER 10000

set configs [config-reader $::script_dir/../share/config $apikey]
set ::buttons $::outputs

readout

proc sim-status {} {
    try { 
	set values [get-sim-status]
	log sim status {*}$values
	msg_cmd WATER "radio [clock seconds] $values" 0 nowait } on error e {
        log-error $e
    }
}

if { [file exists /dev/ttyUSB2] } {
    every 60000 sim-status
}

set WEB_PORT 7777
wapp-start [list -server tcp!*!$WEB_PORT -nowait]

vwait forever
