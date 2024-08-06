
package require jbr::unix

proc log { args } {
    set LOGFILE $::LOGPATH/[clock format [clock seconds] -format "%Y%m%d"]-$::LOGTAIL.log

    set now [clock seconds]
    set msg "$now [clock format $now] [concat $args]"
    echo $msg >> $LOGFILE
    # echo $msg
}

proc log-error { args } {
    log {*}$args
    log $::errorInfo
}
