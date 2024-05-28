#!/usr/bin/tclsh
#

set HOME $env(HOME)
::tcl::tm::path add $HOME/lib/tcl8/site-tcl

package require jbr::func
package require jbr::with
package require jbr::print

set T /dev/ttyUSB2

set COPS {
    0 GSM
    1 GSM-Compact
    2 UTRAN
    3 GSM-w/EGPRS
    4 UTRAN-w/HSDPA
    5 UTRAN-w/HSUPA
    6 UTRAN-w/HSDPA and HSUPA
    7 E-UTRAN
}

set CSQ  {
    2	{ -109	Marginal    }
    3	{ -107	Marginal    }
    4	{ -105	Marginal    }
    5	{ -103	Marginal    }
    6	{ -101	Marginal    }
    7	{  -99	Marginal    }
    8	{  -97	Marginal    }
    9	{  -95	Marginal    }
    10	{  -93	OK          }
    11	{  -91	OK          }
    12	{  -89	OK          }
    13	{  -87	OK          }
    14	{  -85	OK          }
    15	{  -83	Good        }
    16	{  -81	Good        }
    17	{  -79	Good        }
    18	{  -77	Good        }
    19	{  -75	Good        }
    20	{  -73	Excellent   }
    21	{  -71	Excellent   }
    22	{  -69	Excellent   }
    23	{  -67	Excellent   }
    24	{  -65	Excellent   }
    25	{  -63	Excellent   }
    26	{  -61	Excellent   }
    27	{  -59	Excellent   }
    28	{  -57	Excellent   }
    29	{  -55	Excellent   }
    30	{  -53	Excellent   }
    31	{  -51	Excellent   }
}

proc line { tty cmd } {
    puts $tty $cmd
    after 75
    while { true } {
        gets $tty line
        if { $line eq "OK" } {
            break
        }
        if { $line ne "" } { 
            set value $line
        }
    }

    return $value
}

proc ATparse { status line } {
    set line [string map { { } {} {"} {} } $line]
    switch -glob $line {
        +CCLK:* {
            lassign [split $line -] line tz
            set tz 0[expr { $tz*15/60*100 }] ; # This does not work for a TZ with a minutes offset.
            set status [dict replace $status seconds [clock scan $line-$tz -format +CCLK:%y/%m/%d,%H:%M:%S%z]]
        }
        +COPS:* {
            set status [dict replace $status {*}[zip {- - op - } [split [lindex [split $line :] 1] ,]]]
            if { [dict get $status op] eq "" } {
                dict set status op Unknown
            }
        }
        +CSQ:* {
           set status [dict replace $status \
            {*}[zip {db quality} [dict get $::CSQ [lindex [split [lindex [split $line :] 1] ,] 0]]]
            ]
        }
        * { print Huh? $line}
    }

    return [dict remove $status - quality]
}

proc get-sim-status {} {
    with [open $::T RDWR] as tty {
        set status {}
        fconfigure $tty -buffering none -mode 115200,n,8,1 
        set status [ATparse $status [line $tty AT+CSQ]]
        set status [ATparse $status [line $tty AT+COPS?]]
        set status [ATparse $status [line $tty AT+CCLK?]]

        return $status
    }
}
