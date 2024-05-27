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

    set columns [dict keys [db columns $table]]
    print
    print $columns
    print

    set now   [clock seconds]
    set start [seconds $start $now]
    set end   [seconds $end $now]

    try {
        set sql [template:subst {
            select [: c $!columns , { $!c }]
            from (
                select
                    CAST(round(time_recorded/60)*60 as INT) as time_recorded,
                    [: c $!columns , { $!c }]
                from $!table
                where time_recorded > :start AND time_recorded < :end
            )
            group by time_recorded
            order by time_recorded
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
