#!/usr/bin/env tclsh
#

set script_dir [file dirname $argv0]

set HOME $env(HOME)
::tcl::tm::path add $HOME/lib/tcl8/site-tcl

source $script_dir/json/json.tcl
package require jbr::dict
package require jbr::unix
package require jbr::pipe
package require jbr::print
package require jbr::template

proc | { args } { uplevel [list pipe $args] }

set configType {
    object {
        device string channel number gain number
        min number max number zero number scale number
    } 
}

proc toJson { type data } {
    json::encode [json::unite $type $data]
}

proc configToJson { args } {
    toJson $::configType [dict get $::Configs {*}$args]
}

proc webConfig { config } { dict filter $config key min max zero scale averageN }
proc devConfig { config } { dict filter $config key device channel gain }


proc config-expr { type config } {
    set types [dict get $type object]

    set config [dict map {name value} $config {
        if { [dict get $types $name] eq "number" } {
            set value [expr $value]
        } else {
            set value $value
        }
    }]
    return $config
}

proc apikey { key } {
    lappend ::apiKeys $key
    dict set ::apiKeyMap $key $::Host
    dict set ::Config $::Host apikey $key
}

proc device { name config } {
    dict set ::Configs $::Host devices $name $config
}

proc measurement { name config } {
    set config [config-expr $::configType $config]

    dict set ::Configs $::Host measurement $name $config
}

foreach config [glob config/*.conf] {
   set ::Host [file rootname [file tail $config]]
   print $Host
   source $config
}

print $Configs

print [configToJson waterplant measurement flow]

print [| cat ui/index.tmpl | template:subst]
