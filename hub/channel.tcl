
oo::class create channel {
    constructor { nm } {
        variable name $nm
    }

    method scaled {} {
        variable name
        if { [$name get max] ne "" } {
            return [expr max(min(([set ::$name]-[$name get zero]) * [$name get scale], [$name get max]), [$name get min])]
        } else {
            return [set ::$name]
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
