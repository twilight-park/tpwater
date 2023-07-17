
proc check-auth { page } {
    set token [wapp-param token]
    set user  [wapp-param user]
    set pass  [wapp-param pass]

    print check-auth [wapp-param HTTP_HOST]


    set authOk false

    if { $token ne {} } {
        set auth [dict get? $::password $token]
        if { $auth ne {} } {
            set authOk true
        }
    }

    if { $user ne {} } {
        set pass [md5sum $pass]
        set auth [dict get? $::password $user]

        if { $auth ne {} } {
            if { $pass eq [lindex $auth 1] } {
                set token [lindex $auth 1]
                set authOk true
            }
        }
    }


    if { $authOk } {
        wapp-set-cookie token $token
    }

    if { $authOk && $page eq "login" } {
        wapp-redirect /monitor
        return false
    }

    if { $page eq "login" } {
        return true
    }
        
    if { !$authOk } { wapp-redirect /login }
    return $authOk
}

proc http-page { name } {
    try { 

        if { ![check-auth $name] } { return }

        wapp-mimetype text/html
        wapp-cache-control no-cache
        wapp-content-security-policy off

        wapp [value-decode [set ::$name-page:base64]]
    } on error e { print $e }
}

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
