
package require TclOO

namespace eval ::gpio {}
namespace eval ::gpio::gpio {
    set PINMAP {  1 31 2 33 3 35 4 37 }

	oo::class create gpio {

	constructor {} {
			variable state
            foreach { pin p } $::gpio::gpio::PINMAP { dict set state $pin 0 }
        }

        method function { args } {}

        method write { pin st } {
			variable state

			set p [dict get $::gpio::gpio::PINMAP $pin]
            run /usr/bin/lgpio set $p=$st
            dict set state $pin $st
        }
        method read { pin } { 
			variable state
            set s [dict get $state $pin]
            return $s
        }
    }
}

