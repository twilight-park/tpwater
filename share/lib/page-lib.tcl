
wapp-route GET /favicon.ico {
    wapp-mimetype image/x-icon
    try { wapp [bcat static/favicon.ico] } on error e { print $e }
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


