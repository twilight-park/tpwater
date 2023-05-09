set HOME $env(HOME)
::tcl::tm::path add $HOME/lib/tcl8/site-tcl

package require jbr::print

proc value { name type config args } {
    set ::$name $args

    dict set ::$name  type $type
    dict set ::$name $type $config
}

source cards/WaterPlant

print $::Flow



