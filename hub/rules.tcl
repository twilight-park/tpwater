
set ::auto 0

every 5000 {
    if { $::auto } {
        if { $::tank <= 100 } {
            print set ::golf:request 1
            # print set ::thrd:request 1
        }
        if { $::tank >= 102 } {
            print set ::golf:request 0
            # print set ::thrd:request 0
        }
    }
}

