
package require jbr::unix
package require jbr::with
package require jbr::dict
package require jbr::json
package require jbr::seconds

source $script_dir/../pkg/wapp/wapp.tcl
source $script_dir/../pkg/wapp/wapp-routes.tcl
source $script_dir/../pkg/wapp/wapp-static.tcl

source $script_dir/../share/lib/html-lib.tcl
source $script_dir/../share/lib/page-lib.tcl

proc host-alias { device host } {
    foreach { uuid alias } $::known_uuids {
        if { [string eq $device $uuid] } {
            return $alias
        }
    }
    foreach { pattern alias } $::known_hosts {
        if { [string starts-with $host $pattern] } {
            return $alias
        }
    }
    return [expr $device != "" ? $device : $host]
}

wapp-route GET /clients {
    wapp-cache-control no-cache
    wapp-mimetype application/json

    set schema [json::schema [json::decode {
        [{"host": "192.168.1.1", "device": "abc", "timestamp": 123, "alias": "router"}]}
    ]]

    set table [list]
    try {
        foreach { key values } $::queries {
            lassign $values timestamp remote device alias
            lappend table [list host $remote timestamp $timestamp device $device alias $alias]
        }
    } on error msg {
        log-error query2 : $msg
    }

    wapp [json::encode [json::unite $schema $table]]
}

wapp-route GET /query2/lookback/window/frequency {
    wapp-cache-control no-cache
    wapp-mimetype application/json

    if { $lookback eq "" } { return }
    if { $window eq "" } { set window 1m }
    if { $frequency eq "" } { set frequency 1m }

    try {
        set data [rolling_gpm db waterplant time_recorded flow $lookback $window $frequency]
        set data [map row $data {
            lassign $row time flow x y
            list $time [flow scaled $flow]
        }]
        wapp [json::encode [list { array array number } $data]]
    } on error msg {
        log-error query2 : $msg
    }
}

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
                wapp [json::encode [list { array array number } [list [list $start null null] {*}[$result allrows -as lists] [list $end null null]]]]
            }
        }
        set remote [wapp-param REMOTE_ADDR]
        set device [wapp-param device]

        dict set ::queries "$remote-$device" [list [clock seconds] $remote $device [host-alias $device $remote]]

        log $remote Query $table From $start To $end in [timer query get] seconds
    } on error msg {
        log-error $msg
    }
}

wapp-static $::script_dir/../share/static ui nobrowse

wapp-route GET /press {
    html-page press text/html {
        set button [wapp-param button]

        if { $button ni $::outputs } {
            return
        }

        set state [get? ::$button]

        if { ![string is boolean $state] } { return }

        set ::$button:request [expr !$state]
    }
}

wapp-start [list -server $ADDR -nowait]
