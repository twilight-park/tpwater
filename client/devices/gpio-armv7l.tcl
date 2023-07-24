
package require TclOO

namespace eval ::gpio {}
namespace eval ::gpio::gpio {
    set PINMAP {  1 6 2 13 3 19 4 26 }

	oo::class create gpio {

		constructor {} {
        }

        method function { pin mode } {
            piio function $pin $mode
        }

        method write { pin st } {
			variable state
			set p [dict get $::gpio::gpio::PINMAP $pin]

            piio output $p $st
            dict set state $pin $st
            return $st
        }
        method read { pin } { 
			variable state
			set p [dict get $::gpio::gpio::PINMAP $pin]

            set st [piio input $p]
            dict set state $pin $st
            return $st
        }
    }
}

