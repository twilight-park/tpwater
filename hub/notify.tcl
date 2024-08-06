package require jbr::twillio
package require jbr::unix
package require jbr::print
package require jbr::seconds

source $script_dir/noted.cfg

proc notify { type args } {
    set note [dict get $::notifications $type]
    set rate [dict get $note rate]
    set last [dict get $::noted $type]

    if { [clock milliseconds] - $last < [milliseconds $rate] } {
        print Skip Notify $type : $args
        return
    }

    set from [dict get $::notifications PEOPLE [dict get $note from] phone]
    set send [dict get $::notifications SEND driver]

    foreach person [dict get $note people] {

        set to [dict get $::notifications PEOPLE $person phone]
        set msg [dict get $note message]
        dict with args {
            set msg [subst -nocommands [regsub -line -all {(^[ \t]*|[ \t]*$)} $msg {}]]
        }

        log Notify $send $type from: $from to: $person $to : $args
        $send $from $to $msg

        dict set ::noted $type [clock milliseconds]
        echo [subst { set ::noted "$::noted" }] > $::script_dir/noted.cfg
    }
}

proc try-rule { name action } {
    try {
        uplevel $action
    } on error msg {
        log RULE Error: $name $msg
    }
}

