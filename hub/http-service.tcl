
package require jbr::unix
package require jbr::with
package require jbr::dict
package require jbr::seconds

source $script_dir/../pkg/wapp/wapp.tcl
source $script_dir/../pkg/wapp/wapp-routes.tcl
source $script_dir/../pkg/wapp/wapp-static.tcl

source $script_dir/../share/lib/html-lib.tcl
source $script_dir/../share/lib/page-lib.tcl

source $script_dir/../pkg/json/json.tcl


wapp-route GET /query/table/start/end {
    wapp-cache-control no-cache
    wapp-mimetype application/json

    if { $start eq "" } {
        return
    }

    if { $table eq "log" } {
        set table waterplant
    }

    set columns [wapp-param columns]
    if { $columns eq "" } {
        set columns { flow tank }
    }
    timer query start

    set now   [clock seconds]
    set start [seconds $start $now]
    set end   [seconds $end $now]

    try {
        set sql [template:subst {
            select time_measured,
                   [: c $!columns , { 
                       round(max(min((avg($!c) - [!$!c get zero])*[!$!c get scale], [!$!c get max]), [!$!c get min]), 2) as $!c 
                   }]
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
        with stmt = [db prepare $sql] {
            with result = [$stmt execute] {
                wapp [json::encode [list { array array number } [$result allrows -as lists]]]
            }
        }
        log [wapp-param REMOTE_ADDR] Query $table From $start To $end in [timer query get] seconds
    } on error msg {
        log-error $msg
    }
}

wapp-static ~/tpwater/ui ui nobrowse

wapp-route GET /press {
    html-page press text/html {
        set button [wapp-param button]
        if { $button ni $::outputs } {
            return
        }

        set state [get? ::$button]

        if { ![string is boolean $state] } { return }

        set state [expr !$state]
        set ::$button:request $state
    }
}

wapp-start [list -server $ADDR -nowait]
