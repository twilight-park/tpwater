
package require jbr::unix
package require jbr::with

source ~/src/wapp/wapp.tcl
source ~/src/wapp/wapp-routes.tcl
source ~/src/wapp/wapp-static.tcl

source $script_dir/json/json.tcl

proc seconds { time { now "" } } {

    if { $now eq "" } {
	set now [clock seconds]
    }
    if { $time eq "" } {
	return $now
    }

    set time [expr [string map { 
	m "*60" 
	h "*3600" 
	d "*[expr 60*60*24]" 
	w "*[expr 60*60*24*7]" 
	t "*[expr 60*60*24*30]" 
	y "*[expr 60*60*24*365]" 
    } $time]]

    if { $time < 0 } {
	set time [expr $now + $time]
    }

    return $time
}

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
		    select time_measured, flow, pres
		    from $table 
		    where time_measured > :start AND time_measured < :end
		    order by time_measured
		 }]] { $stmt close } {
	    with result = [$stmt execute] { $result close } {
		set d [$result allrows -as lists]

		# foreach time [iota [expr int($start/60) * 60] $end 60] {
		#     dict set data $time [list 0 0]
		# }
		foreach row $d {
		    lassign $row time flow pres
		    set time [expr int($time/60) * 60]
		    dict set data $time [list $flow $pres]
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

wapp-route GET /monitor {
    wapp-mimetype text/html
    wapp-cache-control no-cache
    wapp-content-security-policy off
    wapp [cat ~/tpwater/ui/index.html]
}

proc wapp-default {} {
    wapp-mimetype text/html
    wapp-log info "[wapp-param REMOTE_ADDR] [wapp-param PATH_INFO] Go Away"
    wapp-reply-code ABORT
}

wapp-start [list -server $ADDR -nowait]

