#!/bin/env tclsh
#
set HOME $env(HOME)
::tcl::tm::path add $HOME/lib/tcl8/site-tcl

source $script_dir/migrate-db.tcl
package require tdbc::sqlite3

tdbc::sqlite3::connection create db "$script_dir/check.db"

set schema {
    log {
        { time_measured integer }
        { time_recorded integer }
        { flow real }
        { tank real }
        { golf real }
        { thrd real }
        { pres real }
    }
}

migrate-db db $schema

proc record { time_measured flow tank golf thrd } {
    print record $time_measured $flow $tank $golf $thrd
    set time_recorded [clock seconds]
    sql db { insert into log 
	       (  time_recorded,  time_measured,  flow,  tank,  golf,  thrd) 
	values ( :time_recorded, :time_measured, :flow, :tank, :golf, :thrd ) }
}

