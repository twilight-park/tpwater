
package require jbr::template
package require jbr::template_macro

template-environment create T
T macros $script_dir/../share/html

wapp-route GET /favicon.ico {
    wapp-mimetype image/x-icon
    try { wapp [bcat $::script_dir/../share/static/favicon.ico] } on error e { log-eror $e }
}

wapp-route GET /logout   {
    wapp-clear-cookie token 
    wapp-redirect /login
}

wapp-route GET /values {
    html-page values application/json {
        set page [wapp-param page]

        wapp [template:subst { {
            [: name $!::names { "$!name": [!get? ::$!name], } ]
            "date": [!clock seconds],
            "page": [!get? ::$!page:md5sum]
        } }]

    }
}

proc wapp-default {} {
    wapp-allow-xorigin-params
    html-page [string range [wapp-param PATH_INFO] 1 end]
}
