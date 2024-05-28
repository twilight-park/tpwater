
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

    set end   [clock seconds]
    set start [seconds $start $end]

    try {
        set sql [template:subst {
            select time_recorded,
                   [: c $!columns , { 
                       round(max(min((avg($!c) - [!$!c get zero])*[!$!c get scale], [!$!c get max]), [!$!c get min]), 2) as $!c 
                   }]
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
        with stmt = [db prepare $sql] {
            with result = [$stmt execute] {
                wapp [json::encode [list { array array number } [list $start {*}[$result allrows -as lists] $end]]]
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

        set ::$button:request [expr !$state]
        print set ::$button:request [expr !$state]
    }
}

wapp-start [list -server $ADDR -nowait]
