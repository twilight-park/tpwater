#!/usr/bin/env tclsh
#

set ADDR tcp!data.rkroll.com!7778

set script_dir [file dirname $argv0]

set env(WATER) .:8001
set apikey check:d9ffc43b7a95cca9aabafb611be28a2ac8abc72d

set HOME $env(HOME)
set TPWATER $HOME/tpwater

::tcl::tm::path add $HOME/lib/tcl8/site-tcl

package require jbr::msg
package require jbr::unix
package require jbr::with
package require jbr::print
package require jbr::string
package require jbr::filewatch

source db-setup.tcl
source http-service.tcl

source channel.tcl

msg_server WATER
msg_deny   WATER internettl.org
msg_allow  WATER *
msg_apikey WATER $apikey

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
    print $config
    set ::$config:hash [config-read config/$config]
    set ::$config:md5sum [md5sum [set ::$config:hash]]
}

proc print-var { name varname args } {
    upvar $varname var
    print print-var $name [set var] $args
}

foreach config [glob -directory config -tails *] {
    set ::$config:hash [config-read config/$config]
    set ::$config:md5sum [md5sum [set ::$config:hash]]
    msg_publish WATER $config $config:hash
    lappend ::configs $config
    filewatch config/$config "reload-file $config"

    if { [string ends-with $config -page] } {
        continue
    }
    if { $config eq "password" } {
        foreach { hash auth user } [value-decode [set ::$config:hash]] {
            dict set ::password $hash "$auth $user"
            dict set ::password $user "$auth $hash"
        }
        continue
    }

    set ::$config {}
    foreach { name values } [cat config/$config] {
        if { $name eq "record" || [string starts-with $name "#"]} { continue }

        dict lappend ::$config names $name 
        lappend ::names $name

        channel create $name $name
        $name config $values
        msg_publish WATER $name {} ; # "print-var $name"
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
        foreach name $names value $args {
            set ::$name $value
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

msg_up WATER

check

vwait forever
