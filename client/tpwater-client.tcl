#!/usr/bin/env tclsh
#

set env(WATER) data.rkroll.com:8001

set HOME $env(HOME)
set TPWATER $HOME/tpwater

lappend auto_path $HOME/lib/tcl8/lib 
lappend auto_path /usr/share/tcltk/tcllib1.20
::tcl::tm::path add $HOME/lib/tcl8/site-tcl

package require coroutine::auto

package require jbr::print
package require jbr::func
package require jbr::with
package require jbr::unix
package require jbr::msg

set apikey [cat $HOME/apikey]

set script_dir [file dirname $argv0]

source $script_dir/../share/lib/codec-lib.tcl
source $script_dir/http-service.tcl

source $script_dir/devices/ADS1115.tcl
source $script_dir/devices/MCP342x.tcl
source $script_dir/devices/gpio-[run uname -m].tcl

source $script_dir/sim-status.tcl
source $script_dir/channel.tcl

proc configure { config } {
    try {
        print configure $config

        foreach { name params } $config {
            if { [string index $name 0] eq "#" } { continue }
            if { $name eq "apikey" } { continue }
            if { $name eq "record" } {
                set ::record $params
                continue
            }

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
            }
            $name config $params
            msg_subscribe WATER $name 
            if { [$name get mode] eq "output" } {
                lappend ::outputs $name
                msg_subscribe WATER $name:request {} "set-state $name"
            }
        }

        set ::devices [lsort -uniq $::devices]
    } on error e { print $e }
}

proc set-state { name var args } {
    upvar $var value
    $name write $value
    set ::$name $value
    msg_set WATER $name $value {} async
}

proc reconfig { args } {
    try {
        set config [value-decode $::config]

        cleanup
        configure $config
        readout
    } on error e { print $e }
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
        print record [clock seconds] [zip $args $values]

        try { msg_cmd WATER "rec [clock seconds] $values" 0 nowait 
        } on error e {
            print $e
        }
    } on error e { print record : $e }
}

proc unset? { name } {
    if { [info exists $name] } {
        unset $name
    }
}
proc cleanup {} {
    try {
        foreach after [after info] {
            after cancel $after
        }
        if { [info exists ::devices] } {
            foreach device $::devices {
                unset? ::$device
            }
            unset? ::devices
        }
        if { [info exists ::inputs] } {
            foreach input $::inputs {
                rename $input {}
            }
            unset? ::inputs
        }
        
        unset? ::inputs
    } on error e { print cleanup : $e }
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

proc subscribe-to-names { var args } {
    upvar $var value
    foreach name $value {
        print msg_subscribe WATER $name
        msg_subscribe WATER $name
    }
}

proc passwords { var args } {
    upvar $var value
    set passwords [value-decode $value]
    foreach { hash auth user } $passwords {
        dict set ::password $hash "$auth $user"
        dict set ::password $user "$auth $hash"
    }
}

proc init-cached-value { name variable code } {
    try {
        set ::$variable [cat $::script_dir/../cache/$variable]
    } on error e { print $e }
    msg_subscribe WATER $name $variable [list cache-value $variable $code]
}

proc init-cached-base64-value { name variable { code {} } } {
    try {
        set ::$variable [cat $::script_dir/../cache/$variable]
        value-md5sum ::$variable
        if { $code ne {} } {
            print eval $code ::$variable
            eval $code ::$variable
        }
    } on error e { print $e }

    msg_subscribe WATER $name $variable [list cache-base64-value $variable $code]
}

proc cache-value { name code args } {
    echo [set ::$name] > $::script_dir/../cache/$name
    if { $code ne {} } {
        eval $code ::$name
    }
}

proc cache-base64-value { name code args } {
    echo [set ::$name] > $::script_dir/../cache/$name
    value-md5sum ::$name
    if { $code ne {} } {
        eval $code ::$name
    }
}

msg_client WATER
msg_setreopen WATER 10000
msg_apikey WATER $apikey

msg_subscribe WATER names {} subscribe-to-names

init-cached-value names names subscribe-to-names

init-cached-base64-value     $apikey             config reconfig
init-cached-base64-value    password    password:base64 passwords
init-cached-base64-value status-page status-page:base64 
init-cached-base64-value  login-page  login-page:base64 

proc sim-status {} {

    print msg_cmd WATER "radio [get-sim-status]" 0 nowait
    msg_cmd WATER "radio [get-sim-status]" 0 nowait
}

every 60000 sim-status

vwait forever
