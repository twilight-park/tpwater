
oo::class create channel {
    constructor { nm } {
        variable name $nm
    }

    method scaled { value } {
        variable name
        if { [$name get max] ne "" } {
            return [expr max(min(($value-[$name get zero]) * [$name get scale], [$name get max]), [$name get min])]
        } else {
            return $value
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
