package require jbr::dict

source ../share/lib/channel.tcl

oo::class create dev-channel {
    superclass channel
    variable device channel sample value current config 


    constructor { dev ch sam } {
        set device $dev
        variable channel $ch
        variable sample $sam
        variable value {}
        variable current 0
        variable config {}
    }

    method read {} {
        return [$device read $channel]
    }
    method write { state } {
        if { $state eq "" } { return }

        set current $state
        set value $state
        return [$device write $channel $state]
    }
    method sample { v } {
        if { $sample } {
            lappend value $v
        } else {
            set value $v
        }
    }
    method clear {} {
        set value {}
    }
    method value {} {
        if { $sample } {
            set current [format %.1f [avg $value]]
            set value {}
        } else {
            set current $value
        }

        return $current
    }
    method current { value } {
        set current $value
    }
}

