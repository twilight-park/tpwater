
package require jbr::unix
package require jbr::with
package require jbr::dict
package require jbr::template
package require jbr::seconds

source $TPWATER/pkg/wapp/wapp.tcl
source $TPWATER/pkg/wapp/wapp-routes.tcl
source $TPWATER/pkg/wapp/wapp-static.tcl
source $TPWATER/pkg/json/json.tcl

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

wapp-route GET /favicon.ico {
    wapp-mimetype image/x-icon
    try { wapp [bcat static/favicon.ico] } on error e { print $e }
}

proc check-auth { page } {
    set token [wapp-param token]
    set user  [wapp-param user]
    set pass  [wapp-param pass]

    set authOk false

    if { $token ne {} } {
        set auth [dict get? $::password $token]
        if { $auth ne {} } {
            set authOk true
        }
    }

    if { $user ne {} } {
        set pass [md5sum $pass]
        set auth [dict get? $::password $user]

        if { $auth ne {} } {
            if { $pass eq [lindex $auth 1] } {
                set token [lindex $auth 1]
                set authOk true
            }
        }
    }


    if { $authOk } {
        wapp-set-cookie token $token
    }

    if { $authOk && $page eq "login" } {
        wapp-redirect /monitor
        return false
    }

    if { $page eq "login" } {
        return true
    }
        
    if { !$authOk } { wapp-redirect /login }
    return $authOk
}

proc http-page { name } {
    try { 
        if { ![check-auth $name] } { return }

        wapp-mimetype text/html
        wapp-cache-control no-cache
        wapp-content-security-policy off

        wapp [value-decode [set ::$name-page:hash]]
    } on error e { print $e }
}

wapp-route GET /login   { http-page login }
wapp-route GET /status  { http-page status }
wapp-route GET /monitor { http-page monitor }

wapp-route GET /logout   { 
    wapp-set-cookie token X
    wapp-redirect /login
}

wapp-route GET /press {
    if { ![check-auth press] } { return }

    set b [wapp-param button]
    if { $b ni $::buttons } {
        return
    }
    set state [set ::$b]
    set state [expr !$state]
    set ::$b $state
}

wapp-route GET /values {
    if { ![check-auth values] } { return }

    wapp-mimetype application/json
    wapp-cache-control no-cache
    set page [set ::[wapp-param page]-page:md5sum]

    try {
        wapp [template:subst {
            {
                [: name $!::names { "$!name": [!$!name scaled], }]
                "date": [!clock seconds],
                "page": "$!page"
            }
        }]
    } on error e { print $e }
}

proc wapp-default {} {
    wapp-mimetype text/html
    wapp-log info "[wapp-param REMOTE_ADDR] [wapp-param PATH_INFO] Go Away"
    wapp-reply-code ABORT
}

wapp-start [list -server $ADDR -nowait]

