
set ::pump_off_time  0
set ::golf:request   0
set ::thrd:request   0

proc pump-off {} {
    if { [string is true -strict [set ::golf:request]] || [string is true -strict [set ::thrd:request]] } {
        set ::golf:request 0
        set ::thrd:request 0
        set ::pump_off_time [clock seconds]
    }
}

proc pump-on {} {
    if { [expr { [clock seconds] - $::pump_off_time }] >= 300 } {
        set ::golf:request 1
        set ::thrd:request 1
    }
}

every 5000 {
    try-rule auto {
        if { [set ::waterplant:late] } {
            pump-off
        } elseif { $::tank <= 101.5 } {
            pump-on
        } elseif { $::tank > 102.5 } {
            pump-off
        }
    }
}

cron { Mon at 10:05 } {
    try-rule NOTE {
        notify NOTE
    }
}

cron { every 2m at 15s } {
    try-rule LOWTANK {
        if { $::tank < 95 } {
            notify LOWTANK level $::tank
        }
    }
}

cron { every 2m at 5s } {
    try-rule LEAK {
        set rate 30

        set data [rolling_gpm db waterplant time_recorded flow 0 10.5m 1s 28]
        set f10w [flow scaled [lindex $data 0 1]]

        log Flow10 f10w $f10w >= $rate?

        if { $f10w >= $rate } {
            notify LEAK rate $rate f10w $f10w
        }
    }
}
