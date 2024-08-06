
package require jbr::cron
package require jbr::seconds
package require jbr::twillio

source $script_dir/rolling_gpm.tcl

proc try-rule { name action } {
    try {
        uplevel $action
    } on error msg {
        log RULE Error: $name $msg
    }
}

every 5000 {
    try {
        if { $::auto } {
            if { $::tank <= 101.5 } {
                set ::golf:request 1
                set ::thrd:request 1
            }
            if { $::tank > 102.5 } {
                set ::golf:request 0
                set ::thrd:request 0
            }
        }
    } on error msg {
        log RULE Error $msg
    }
}

cron { Mon at 10:05 } {
    try-rule NOTE {
        notify NOTE 
    }
}

cron { every 2m at 5s } {
    try-rule LEAK {
        set rate 30

        set data [rolling_gpm db waterplant time_recorded flow 0 10.5m 1s]
        set f10w [flow scaled [lindex $data 0 1]]

        log Flow10 f10w $f10w >= $rate?

        if { $f10w >= $rate } {
            notify LEAK rate $rate f10w $f10w
        }
    }
}
