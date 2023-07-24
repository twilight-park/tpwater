
package require jbr::template
package require jbr::template_macro

template-environment create T
T macros $script_dir/../share/html

wapp-route GET /favicon.ico {
    wapp-mimetype image/x-icon
    try { wapp [bcat $::script_dir/../share/static/favicon.ico] } on error e { log-eror $e }
}

wapp-route GET /login   { http-page login }
wapp-route GET /status  { http-page status }
wapp-route GET /monitor { http-page monitor }

wapp-route GET /logout   { 
    wapp-set-cookie token X
    wapp-redirect /login
}

wapp-route GET /values {
    http-page values application/json {
        set page [wapp-param page]

        wapp [template:subst { {
            [: name $!::names { "$!name": [!get? ::$!name], } ]
            "date": [!clock seconds],
            "page": "[!get? ::$!page-page:md5sum]"
        } }]

    }
}

proc wapp-default {} {
    wapp-mimetype text/html
    wapp-log info "[wapp-param REMOTE_ADDR] [wapp-param PATH_INFO] Go Away"
    wapp-reply-code ABORT
}

