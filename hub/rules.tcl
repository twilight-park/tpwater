
set ::auto 0

every 5000 {
    try {
        if { $::auto } {
            if { $::tank <= 100 } {
                set ::golf:request 1
                # set ::thrd:request 1
            }
            if { $::tank >= 101 } {
                set ::golf:request 0
                # set ::thrd:request 0
            }
        }
    } on error msg {
        print RULE $msg
    }
}

