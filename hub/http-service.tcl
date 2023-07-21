
package require jbr::unix
package require jbr::with
package require jbr::dict
package require jbr::seconds

source $script_dir/../pkg/wapp/wapp.tcl
source $script_dir/../pkg/wapp/wapp-routes.tcl
source $script_dir/../pkg/wapp/wapp-static.tcl

source $script_dir/../share/lib/http-lib.tcl
source $script_dir/../share/lib/page-lib.tcl

source $script_dir/../pkg/json/json.tcl


wapp-route GET /query/log/start/end {
    wapp-cache-control no-cache

    timer query start

    wapp-mimetype application/json
    set table waterplant

    if { $start eq "" } {
        return
    }

    set now   [clock seconds]
    set start [seconds $start $now]
    set end   [seconds $end $now]

    try {
        with stmt = [db prepare [subst {
                select round(time_measured/60)*60 as time_measured, 
                       max(min((avg(flow) - [flow get zero])*[flow get scale], [flow get max]), [flow get min]) as flow, 
                       max(min((avg(tank) - [tank get zero])*[tank get scale], [tank get max]), [tank get min]) as tank
                from $table 
                where time_measured > :start AND time_measured < :end
                group by time_measured
                order by time_measured
            }]] { $stmt close } {
            with result = [$stmt execute] { $result close } {
                set d [$result allrows -as lists]

                foreach row $d {
                    lassign $row time flow tank
                    dict set data $time [list $flow $tank]
                }
                set dlist [list]
                foreach { time value } $data {
                    lappend dlist [list $time [lindex $value 0] [lindex $value 1]]
                }

                wapp [json::encode [list { array array number } $dlist]]
            }
        }
        wapp-log info "[wapp-param REMOTE_ADDR] Query $table From $start To $end in [timer query get] seconds"
    } on error msg {
        wapp-log error $msg
    }
}

wapp-static ~/tpwater/ui ui nobrowse

wapp-route GET /press {
    http-page press text/html {
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
