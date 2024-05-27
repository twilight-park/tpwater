#!/usr/bin/env tclsh
#

set script_dir [file dirname $argv0]
set HOME $env(HOME)
::tcl::tm::path add $HOME/lib/tcl8/site-tcl

package require jbr::unix
package require jbr::with
package require jbr::dict
package require jbr::print
package require jbr::template
package require jbr::seconds

source $script_dir/pkg/json/json.tcl

package require tdbc::sqlite3


    set dbname  [lindex $argv 0]
    set table   [lindex $argv 1]
    set start   [lindex $argv 2]
    set end     [lindex $argv 3]

if { ![file exists $dbname] } {
    print No DB
    exit 1
}

tdbc::sqlite3::connection create db $dbname

    set columns { flow tank }

    set now   [clock seconds]
    set start [seconds $start $now]
    set end   [seconds $end $now]

    try {
        set sql [template:subst {
            select time_measured, [: c $!columns , { $!c }]
            from (
                select
                    CAST(round(time_measured/60)*60 as INT) as time_measured,
                    [: c $!columns , { $!c }]
                from $!table
                where time_measured > :start AND time_measured < :end
            )
            group by time_measured
            order by time_measured
        }]
        print $start $end
        print $sql

        with stmt = [db prepare $sql] {
            with result = [$stmt execute] {
                foreach row [$result allrows -as lists] {
                    print $row
                }
            }
        }
    } on error msg {
        print log-error $msg
    }
