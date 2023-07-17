
proc run { args } {
    with [open "| $args"] as p {
        return [lindex [read $p] 0]
    }
}

proc md5sum { value } {
    return [run md5sum - << $value]
}

proc value-md5sum { var args } {
    print md5sum $var
    set ::$var:md5sum [md5sum [set $var]]
}

proc value-encode { config } {
    return [binary encode base64 [zlib deflate $config]]]
}

proc value-decode { value } {
    if { $value eq "" } {
        error "No value to decode"
    }
    return [zlib inflate [binary decode base64 $value]]
}

