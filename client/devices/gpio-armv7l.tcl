
package require TclOO

namespace eval ::gpio {}
namespace eval ::gpio::gpio {
    set PINMAP {  6 31 13 33 19 35 26 37 }

	oo::class create gpio {

		constructor {} {
        }

        method function { pin mode } {
            piio function $pin $mode
        }

        method write { pin st } {
			variable state


            print piio output $pin $st
            piio output $pin $st
            dict set state $pin $st
            return $st
        }
        method read { pin } { 
			variable state
            print set st [piio input $pin]
            set st [piio input $pin]
            dict set state $pin $st
            return $st
        }
    }
}

