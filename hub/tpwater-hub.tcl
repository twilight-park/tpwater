#!/usr/bin/env tclsh
#

set script_dir [file dirname $argv0]
source $script_dir/hub.cfg

set HUB true

set ADDR data.rkroll.com:$WEB_PORT
set env(WATER) .:$MSG_PORT

set HOME $env(HOME)

::tcl::tm::path add $HOME/lib/tcl8/site-tcl

package require jbr::msg
package require jbr::unix
package require jbr::with
package require jbr::print
package require jbr::string

set LOGPATH $::script_dir/../log
set LOGTAIL [file rootname [file tail $::argv0]]

source $script_dir/../share/lib/channel.tcl
source $script_dir/../share/lib/codec-lib.tcl
source $script_dir/../share/lib/log.tcl
source $script_dir/../share/lib/passwd-reader.tcl

source $script_dir/db-setup.tcl
source $script_dir/http-service.tcl

proc every {ms body} {
    after $ms [list after idle [namespace code [info level 0]]]
    try $body
}

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
    set ::config {}
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
}

proc set-state { name var args } {
    upvar $var value
    set ::$name $value
}

msg_srvproc WATER radio { time_measured args } {
    upvar sock sock
    set apikey [msg_getkey WATER $sock]
    set config [dict get $::apikeyMap $apikey]

    db:record radio [clock seconds] station $config {*}$args
}

msg_srvproc WATER rec { seconds args } {
    upvar sock sock

    try {
        set apikey [msg_getkey WATER $sock]
        set config [dict get $::apikeyMap $apikey]
        set names  [dict get [set ::$config] names]

        set now [clock seconds]

        set delta [expr { abs($now - $seconds) }]
        if { $delta > 2 } {
            log Oops $config $now $seconds : $delta
        }

        set last [set ::$config:last]
        set delta [expr { abs($seconds - $last) }]
        if { $last != 0 && $delta > 25 } {
            log Dropped $delta seconds from $last to $seconds
        }
        set ::$config:last $seconds
        set ::l$config:ate false

        set ::$config:last $seconds
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
    if { !$late && $delta > 25 } {
        log "Packet late $delta seconds at $now"
        set ::$config:late true
    }
}

set ::apikeyMap {}

passwd-reader $::script_dir/../password

set configs [config-reader $::script_dir/../share/config]

msg_up WATER
msg_apikey WATER [dict keys $::apikeyMap]

foreach config $configs {
    every 1000 check $config
}

source $script_dir/rules.tcl


vwait forever
