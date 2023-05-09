
package require jbr::unix

set APPNAME [file rootname [file tail $::argv0]]

proc log { msg } {
    set LOGFILE log/[clock format [clock seconds] -format "%Y%m%d"]-$::APPNAME.log

    set msg "[clock format [clock seconds]] $msg"
    echo $msg >> $LOGFILE
    echo $msg
}

