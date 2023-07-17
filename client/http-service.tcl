
set ADDR tcp!*!7777

package require jbr::template

source $TPWATER/pkg/wapp/wapp.tcl
source $TPWATER/pkg/wapp/wapp-routes.tcl
source $TPWATER/pkg/wapp/wapp-static.tcl

proc get? { name } {
    if { [info exists $name] } {
        set value [set $name]
        if { $value eq "" } {
            return {""}
        }

        return [set $name]
    } else {
        return {"?"}
    }
}

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

wapp-route GET /favicon.ico {
    wapp-mimetype image/x-icon
    try { wapp [bcat $::script_dir/static/favicon.ico] } on error e { print $e } 
}

wapp-route GET /status {
    wapp-mimetype text/html
    wapp-cache-control no-cache
    wapp-content-security-policy off

    try { wapp [template:subst [value-decode ${::status-page}]] } on error e { print $e } 
}

wapp-route GET /press {
    set b [wapp-param button]
    if { $b ni $::outputs } {
        return
    }
    set state [$b read]
    set state [expr !$state]
    $b write $state
    set ::$b $state

    msg_set WATER $b:request $state {} async
}

wapp-route GET /logout   {
    wapp-set-cookie token X
    wapp-redirect /login
}

proc wapp-default {} {
    wapp-mimetype text/html
    wapp-log info "[wapp-param REMOTE_ADDR] [wapp-param PATH_INFO] Go Away"
    wapp-reply-code ABORT
}

 wapp-start [list -server $ADDR -nowait]
