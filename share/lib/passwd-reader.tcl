
proc passwd-reader { passwd } {
    foreach { hash auth user } [cat $passwd] {
        dict set ::password $hash "$auth $user"
        dict set ::password $user "$auth $hash"
    }
}

