#!/bin/env tclsh
#
set HOME $env(HOME)
::tcl::tm::path add $HOME/lib/tcl8/site-tcl

source $script_dir/migrate-db.tcl
package require tdbc::sqlite3

tdbc::sqlite3::connection create db "$script_dir/tpwater.db"

set schema {
   waterplant  {
        { time_measured integer }
        { time_recorded integer }
        { flow real }
        { tank real }
        { thrd real }
    }
   golfcourse  {
        { time_measured integer }
        { time_recorded integer }
        { golf real }
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
    set time_recorded [clock seconds]
    dict with args [template:subst {
        sql db { insert into $!table
               (  time_recorded,  time_measured,  [!join [!dict keys $!args] ",  "])
        values ( :time_recorded, :time_measured, [!join [: key [!dict keys $!args] { :$!key }]  ", "] ) }
    }]
}

proc record-waterplant { table time_measured flow tank thrd } {
    print [clock format [clock seconds] -format "%y-%m-%d %H:%M:%S"] $table $time_measured $flow $tank $thrd
    set time_recorded [clock seconds]
    sql db [subst { insert into $table 
               (  time_recorded,  time_measured,  flow,  tank,  thrd) 
        values ( :time_recorded, :time_measured, :flow, :tank, :thrd ) 
    }]
}

proc record-golfcourse { table time_measured golf } {
    print [clock format [clock seconds] -format "%y-%m-%d %H:%M:%S"] $table $time_measured $golf 
    set time_recorded [clock seconds]
    sql db [subst { insert into $table 
               (  time_recorded,  time_measured,  golf) 
        values ( :time_recorded, :time_measured, :golf ) 
    }]
}

