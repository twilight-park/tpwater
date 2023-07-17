#!/usr/bin/env tclsh
#

set ADDR tcp!data.rkroll.com!7778
set env(WATER) .:8001

set script_dir [file dirname $argv0]
source $script_dir/hub.cfg

set ADDR tcp!data.rkroll.com!$WEB_PORT
set env(WATER) .:$MSG_PORT

set HOME $env(HOME)
set TPWATER $HOME/tpwater

::tcl::tm::path add $HOME/lib/tcl8/site-tcl

#package require jbr::msg
source ../pkg/jbr.tcl/msg/msg.tcl

package require jbr::unix
package require jbr::with
package require jbr::print
package require jbr::string
package require jbr::filewatch

source $script_dir/db-setup.tcl
source $script_dir/http-service.tcl

source $script_dir/channel.tcl

msg_server WATER
msg_deny   WATER internettl.org
msg_allow  WATER *

proc run { args } {
    with [open "| $args"] as p {
        return [lindex [read $p] 0]
    }
}

proc md5sum { value } {
    return [run md5sum - << $value]
}

proc value-encode { config } {
    return [binary encode base64 [zlib deflate $config]]]
}
proc value-decode { value } {
    return [zlib inflate [binary decode base64 $value]]
}
proc config-read { config } {
    return [value-encode [cat $config]]
}

proc reload-file { config } {
    print reload file $config
    set ::$config:base64 [config-read config/$config]
    set ::$config:md5sum [md5sum [set ::$config:base64]]
}

proc print-var { name varname args } {
    upvar $varname var
    print print-var $name [set var] $args
}


foreach config [glob -directory $script_dir/config -tails *] {
    set ::$config:base64 [config-read $script_dir/config/$config]
    set ::$config:md5sum [md5sum [set ::$config:base64]]

    filewatch $script_dir/config/$config "reload-file $config"

    if { [string equal $config password] } {
        msg_publish WATER $config $config:base64
        foreach { hash auth user } [cat $script_dir/config/$config] {
            dict set ::password $hash "$auth $user"
            dict set ::password $user "$auth $hash"
        }
    }

    if { [string ends-with $config -page] } {
        msg_publish WATER $config $config:base64
        continue
    }

    if { [string ends-with $config .cfg] } {
        set configuration [cat $script_dir/config/$config]
        set _names {}
        foreach { name values } $configuration {
            if { $name eq "record" || [string starts-with $name "#"]} { continue }
            if { $name eq "apikey" } {
                set apikey $values
                lappend apikeys $apikey
                continue
            }

            lappend _names $name 
            lappend ::names $name

            channel create $name $name
            $name config $values
            msg_publish WATER $name {} ; # "print-var $name"
            if { [$name get mode] eq "out" } {
                msg_publish WATER $name:request {} ; # "print-var $name"
                lappend ::outputs $name
            }
        }
        set ::$apikey $configuration
        msg_publish WATER $apikey $config:base64
        dict set ::$apikey names $_names
    }
}
set buttons $names

set last 0
set late true

msg_srvproc WATER rec { seconds args } {
    try {
        set now [clock seconds]

        set delta [expr { abs($now - $seconds) }]
        if { $delta > 2 } {
            print Oops $seconds : $delta
        }

        set delta [expr { abs($seconds - $::last) }]
        if { $::last != 0 && $delta > 25 } {
            print Dropped $delta seconds from $::last to $seconds
        }
        set ::last $seconds
        set ::late false

        record $seconds {*}$args

        upvar sock sock
        set names [dict get [set ::[msg_getkey WATER $sock]] names]
        try {
            msg_setting $sock
            foreach name $names value $args {
                set ::$name [$name scaled $value]
            }
        } finally {
            msg_setting {}
        }
    } on error e { print $e }
}

proc check {} {
    after 1000 check
    set now [clock seconds]
    set delta [expr { abs($now - $::last) }]

    if { !$::late && $delta > 25 } {
        print "Packet late $delta seconds at $now"
        set ::late true
    }
}

print Global Names $::names
msg_publish WATER names
msg_apikey WATER $apikeys
msg_up WATER

check

vwait forever
