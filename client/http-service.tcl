
set ADDR tcp!*!7777

package require jbr::template

source $TPWATER/pkg/wapp/wapp.tcl
source $TPWATER/pkg/wapp/wapp-routes.tcl
source $TPWATER/pkg/wapp/wapp-static.tcl

source $script_dir/../share/lib/http-lib.tcl
source $script_dir/../share/lib/page-lib.tcl

wapp-route GET /press {
    set b [wapp-param button]
    if { $b ni $::names } {
        return
    }

    try {

        if { $b in $::outputs } {
            set state [$b read]
            set state [expr !$state]
            $b write $state
            set ::$b $state
            msg_set WATER $b $state {} async
        } else {
            set state [set ::$b]
            set state [expr !$state]
            msg_set WATER $b:request $state {} async
        }
    } on error e { log-error $e }
}

 wapp-start [list -server $ADDR -nowait]
