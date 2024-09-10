#!/usr/bin/env tclsh
#
package require jbr::msg
package require jbr::unix
package require jbr::with
package require jbr::print
package require jbr::string
package require jbr::seconds
package require jbr::cron
package require jbr::seconds
package require jbr::twillio

set script_dir [file dirname $argv0]
source $script_dir/hub.cfg

set HUB true

set ADDR data.rkroll.com:$WEB_PORT
set ADDR *:$WEB_PORT
set env(WATER) .:$MSG_PORT

set LOGPATH $::script_dir/../log
set LOGTAIL [file rootname [file tail $::argv0]]

source $script_dir/../share/lib/log.tcl

source $script_dir/../share/lib/channel.tcl
source $script_dir/../share/lib/codec-lib.tcl
source $script_dir/../share/lib/passwd-reader.tcl

source $script_dir/notify.tcl
source $script_dir/db-setup.tcl
source $script_dir/http-service.tcl
source $script_dir/rolling_gpm.tcl

msg_server WATER
msg_deny   WATER internettl.org
msg_allow  WATER *

every 1000 {
    set ::clk [clock seconds]
}
msg_publish WATER clk


proc print-var { name varname args } {
    upvar $varname var
    log print-var $name [set var] $args
}

proc config-reader { dir } {
    set ::names {}
    set ::outputs {}

    foreach config [glob -directory $dir -tails *.cfg] {
        set configName [file rootname [file tail $config]]
        lappend configs $configName

        print $config
        set configuration [cat $dir/$config]
        print $configuration
        print

        foreach { name params } $configuration {
            if { $name eq "record" || [string starts-with $name "#"]} { continue }
            if { $name eq "apikey" } {
                if { [string length $params] > 10 } {
                    dict set ::apikeyMap $params $configName
                }
                continue
            }

            lappend ::names $name

            channel create $name $name
            $name config $params
            set ::$name ??
            msg_publish WATER $name {} 
            dict lappend ::$configName names $name

            if { [$name get mode] eq "output" } {
                msg_publish WATER $name:request 
                if { $config eq "hub.cfg" } {
                    trace add variable ::$name:request write "set-state $name"
                }
                lappend ::outputs $name
            }
        }
    }

    foreach config $configs {
        set ::$config:last 0
        set ::$config:late true
    }

    return $configs
}

proc set-state { name var args } {
    upvar $var value
    set ::$name $value

    save-state
}
proc save-state {} {
    echo [subst {
        set auto $::auto
    }] > $::script_dir/state.cfg
}

msg_srvproc WATER radio { time_measured args } {
    upvar sock sock
    set apikey [msg_getkey WATER $sock]
    set config [dict get $::apikeyMap $apikey]

    dict set ::ping $config [clock seconds]

    db:record radio [clock seconds] station $config {*}$args
}

msg_srvproc WATER rec { seconds args } {
    upvar sock sock

    try {
        set apikey [msg_getkey WATER $sock]
        set config [dict get $::apikeyMap $apikey]
        set names  [dict get [set ::$config] names]

        dict set ::queries [msg_peer WATER $sock] [list [clock seconds] $config]

        set now [clock seconds]

        set delta [expr { abs($now - $seconds) }]
        if { $delta > 2 } {
            # log Oops $config $now $seconds : $delta
        }

        set last [set ::$config:last]
        set delta [expr { abs($seconds - $last) }]
        if { $last != 0 && $delta > 60 } {
            # log Dropped $delta seconds from $last to $seconds
        }
        set ::$config:late false
        set ::$config:last $now
        db:record $config $seconds {*}[zip $names $args]


        try {
            msg_setting $sock
            foreach name $names value $args {
                set ::$name [$name scaled $value]
            }
        } finally {
            msg_setting {}
        }
    } on error e { log-error $e }
}

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

set ::apikeyMap {}

passwd-reader $::script_dir/../password

set configs [config-reader $::script_dir/../share/config]
source $script_dir/state.cfg
source $script_dir/rules.tcl

msg_up WATER
msg_apikey WATER localhost
msg_apikey WATER [dict keys $::apikeyMap]

foreach config $configs {
    every 1000 "check $config"
}

vwait forever
