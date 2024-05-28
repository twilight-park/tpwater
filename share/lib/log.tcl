
package require jbr::unix

proc log { args } {
    set LOGFILE $::LOGPATH/[clock format [clock seconds] -format "%Y%m%d"]-$::LOGTAIL.log

    set msg "[clock format [clock seconds]] [concat $args]"
    echo $msg >> $LOGFILE
    # echo $msg
}

proc log-error { args } {
    log {*}$args
    log $::errorInfo
}
