package require jbr::dict

oo::class create channel {
    constructor { nm dev ch sam } {
        variable name $nm
        variable device $dev
        variable channel $ch
        variable sample $sam
        variable value {}
        variable current 0
    }

    method read {} {
        variable device 
        variable channel
        return [$device read $channel]
    }
    method write { state } {
        if { $state eq "" } { return }

        variable device 
        variable channel
        variable current
        variable value

        set current $state
        set value $state
        return [$device write $channel $state]
    }
    method sample { v } {
        variable name
        variable sample
        variable value

        if { $sample } {
            lappend value $v
        } else {
            set value $v
        }
    }
    method clear {} {
        variable value
        set value {}
    }
    method value {} {
        variable name
        variable value
        variable sample
        variable current

        if { $sample } {
            set current [format %.1f [avg $value]]
            set value {}
        } else {
            set current $value
        }

        return $current
    }
    method current { value } {
        variable current
        set current $value
    }
    method scaled { value } {
        variable config

        dict with config {
            if { [info exists max] } {
                return [expr max(min(($value-$zero) * $scale, $max), $min)]
            } else {
                return $value
            }
        }
    }
    method config { c } {
        variable config $c
    }
    method get { key } {
        variable config
        return [dict get? $config $key]
    }
}

