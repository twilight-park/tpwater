
set ADDR tcp!*!7777

package require jbr::template

source $TPWATER/pkg/wapp/wapp.tcl
source $TPWATER/pkg/wapp/wapp-routes.tcl
source $TPWATER/pkg/wapp/wapp-static.tcl

source $script_dir/../share/lib/http-lib.tcl
source $script_dir/../share/lib/page-lib.tcl

wapp-route GET /values {
    wapp-mimetype application/json
    wapp-cache-control no-cache

    try {
        wapp [template:subst { {
                [: name $!::names { "$!name": [!get? ::$!name], } ] 
                "date": [!clock seconds], 
                "page": "[!get? ::status-page:md5sum]" 
            } }]
    } on error e { print $e }
}

wapp-route GET /status {
    wapp-mimetype text/html
    wapp-cache-control no-cache
    wapp-content-security-policy off

    try { wapp [template:subst [value-decode ${::status-page}]] } on error e { print $e } 
}

wapp-route GET /press {
    set b [wapp-param button]
    if { $b ni $::names } {
        return
    }

    if { $b in $::outputs } {
        set state [$b read]
        set state [expr !$state]
        $b write $state
        set ::$b $state
        msg_set WATER $b $state {} async
    } else {
         msg_set WATER $b:request $state {} async
     }
}

 wapp-start [list -server $ADDR -nowait]
