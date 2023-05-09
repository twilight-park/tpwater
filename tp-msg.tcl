#!/usr/bin/env tclsh
#

set script_dir [file dirname $argv0]

set env(WATER) .:8000
set apikey 1a200518a6aa64410f57f7c2472b1e6c

set HOME $env(HOME)
::tcl::tm::path add $HOME/lib/tcl8/site-tcl

set ADDR tcp!data.rkroll.com!7777

source $script_dir/db-setup.tcl
source $script_dir/http-service.tcl

package require jbr::print
package require jbr::msg

msg_server WATER
msg_deny   WATER internettl.org
msg_allow  WATER *
msg_apikey WATER $apikey

proc msg-record { server sock msgid cmd time_measured flow pres } {
    record $time_measured $flow $pres
}

msg_register WATER rec {} msg-record

msg_up WATER

vwait forever
