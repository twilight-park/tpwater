
package require jbr::unix
package require jbr::with

source ~/src/wapp/wapp.tcl
source ~/src/wapp/wapp-routes.tcl
source $script_dir/json/json.tcl

proc page { name } {
    wapp-mimetype text/html
    wapp "<H4> Twilight Park Water System Monitor</H4>"
    wapp "<H2> $name </H2>"
    wapp [cat ./docs/$name]
}
wapp-route GET /Setup.html 	{ page Setup 	}
wapp-route GET /API.html   	{ page API 	}
wapp-route GET /Droplet.html 	{ page Droplet 	}

wapp-route GET /query/log/start/end {
    timer query start

    wapp-mimetype application/json
    set table $log

    if { $start eq "" } {
	return
    }

    set start [expr [string map { 
	m "*60" 
	h "*3600" 
	d "*[expr 60*60*24]" 
	w "*[expr 60*60*24*7]" 
	y "*[expr 60*60*24*365]" 
    } $start]]
    if { $start < 0 } {
	set start [expr [clock seconds] + $start]
    }
    if { $end eq "" } {
	set end [clock seconds]
    }

    try {
	with stmt = [db prepare [subst {
		    select time_measured, flow
		    from $table 
		    where time_measured > :start AND time_measured < :end
		    order by time_measured
		 }]] { $stmt close } {
	    with result = [$stmt execute] { $result close } {
		set d [$result allrows -as lists]

		foreach time [iota [expr $start/60 * 60] $end 60] {
		    dict set data $time 0
		}
		foreach row $d {
		    lassign $row time value
		    set time [expr $time/60 * 60]
		    dict set data $time $value
		}
		set dlist [list]
		foreach { time value } $data {
		    lappend dlist [list $time $value]
		}

		wapp [json::encode [list { array array number } $dlist]]
	    }
	}
	wapp-log info "[wapp-param REMOTE_ADDR] Query $table From $start To $end in [timer query get] seconds"
    } on error msg {
	wapp-log error $msg
    }
}

proc wapp-default {} {
    wapp-log warn "Go away [wapp-param REMOTE_ADDR]"
}

wapp-start [list -server $ADDR -nowait]

