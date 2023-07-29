
oo::class create channel {
    variable config

    method scaled { value } {
        dict with config {
            if { [info exists max] } {
                return [format %.${precision}f [expr max(min(($value-$zero) * $scale, $max), $min)]]
            } else {
                return $value
            }
        }
    }
    method config { c } {
        set config $c
    }
}
