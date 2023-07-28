
package require jbr::string

proc is-localhost? {} {
    return [string starts-with [wapp-param HTTP_HOST] "localhost:"]
}

proc check-auth { page } {
    if { [is-localhost?] } {
        return true
    }
        
    set token [wapp-param token]
    set user  [wapp-param user]
    set pass  [wapp-param pass]


    set authOk false

    if { ![info exists ::password] } {
        log No password file
        return false
    }

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
        wapp-redirect /[wapp-param page monitor]
        return false
    }

    if { $page eq "login" } {
        return true
    }
        
    if { !$authOk } {
        wapp-redirect /login?page=$page
    }
    return $authOk
}

proc get? { name } {
    if { [info exists $name] } {
        set value [set $name]
        if { ![string is double $value] } {
            return "\"$value\""
        }
        if { $value eq "" } {
            return {""}
        }

        return [set $name]
    } else {
        return {"?"}
    }
}

proc html-read { page } {
    set hfile $::script_dir/../share/html/$page.page

    if { ![info exists :$page:mtime] || [set ::$page:mtime] < [file mtime $hfile] } {
        set ::$page:text   [cat $hfile]
        set ::$page:mtime  [file mtime $hfile]
        set ::$page:md5sum [md5sum [set ::$page:text]]
    }

    return [set ::$page:text]
}

proc http-page { page { mime text/html } { 
        code { wapp [T subst [html-read $page]] } 
    } 
} {
    try { 
        if { ![check-auth $page] } { return }

        wapp-mimetype $mime
        wapp-cache-control no-cache
        wapp-content-security-policy off

        eval $code
    } on error e { log-error $e }
}
