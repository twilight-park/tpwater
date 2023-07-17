
package require jbr::unix
package require jbr::with
package require jbr::dict
package require jbr::template
package require jbr::seconds

source pkg/wapp/wapp.tcl
source pkg/wapp/wapp-routes.tcl
source pkg/wapp/wapp-static.tcl

source ../share/lib/http-lib.tcl
source ../share/lib/page-lib.tcl

source pkg/json/json.tcl

wapp-route GET /query/log/start/end {
    wapp-cache-control no-cache

    timer query start

    wapp-mimetype application/json
    set table $log

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

wapp-route GET /login   { http-page login }
wapp-route GET /status  { http-page status }
wapp-route GET /monitor { http-page monitor }

wapp-route GET /press {
    set b [wapp-param button]
    if { $b ni $::outputs } {
        return
    }

    set state [get? ::$b]

    if { ![string is boolean $state] } { return }

    set state [expr !$state]
    set ::$b:request $state
}

wapp-route GET /values {
    wapp-mimetype application/json
    wapp-cache-control no-cache

    try {
        wapp [template:subst { {
                [: name $!::names { "$!name": [!get? ::$!name], } ]
                "date": [!clock seconds],
                "page": "[!get? ::status-page:md5sum]"
            } }]
    } on error e { print $e }
}

wapp-start [list -server $ADDR -nowait]
