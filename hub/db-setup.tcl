#!/bin/env tclsh
#
set HOME $env(HOME)
::tcl::tm::path add $HOME/lib/tcl8/site-tcl

source $script_dir/migrate-db.tcl
package require tdbc::sqlite3

tdbc::sqlite3::connection create db "$script_dir/../tpwater.db"

set schema {
    config {
        { name string }
        { value string }
    }

    waterplant  {
        { time_measured integer }
        { time_recorded integer }
        { flow real }
        { tank real }
        { chan2 real }
        { chan3 real }
        { thrd real }
    }
    golfcourse  {
        { time_measured integer }
        { time_recorded integer }
        { golf real }
        { giac integer }
    }
    thirdlevel  {
        { time_measured integer }
        { time_recorded integer }
        { thrd real }
        { tiac integer }
    }
    testcard {
        { time_measured integer }
        { time_recorded integer }
        { ana0 real }
        { gpo0  integer }
    }

    radio {
        { time_measured integer }
        { time_recorded integer }
        { station       string  }
        { op            string  }
        { db            integer }
    }
}

migrate-db db $schema

proc db:record { table time_measured args } {
    log db:record $table $time_measured {*}$args 
    set time_recorded [clock seconds]
    dict with args [template:subst {
        sql db { insert into $!table
               (  time_recorded,  time_measured,  [!join [!dict keys $!args] ",  "])
        values ( :time_recorded, :time_measured, [!join [: key [!dict keys $!args] { :$!key }]  ", "] ) }
    }]
}

proc db-set { name value } {
    sql db { INSERT OR REPLACE INTO status (name, value) VALUES ("%name", "%value") WHERE name = %name }
}
