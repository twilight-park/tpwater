
package require TclOO
package require piio 1.2

proc swap { x } {
	return [expr { ( ($x & 0xFF00) >> 8 ) | ( ($x & 0x00FF) << 8 ) }]
}

namespace eval ::i2c {}
namespace eval ::i2c::MCP342x {
	# I2C address of the device
	set DEFAULT_ADDRESS 0x68

	# MCP3425/6/7/8 Configuration Command Set
	set CMD_CONVERSION_MASK 0x80
	set CMD_CONVERSION_READY 0x00 		; # Conversion Complete: 0=data ready, 1=not_finished.
	set CMD_CONVERSION_INITIATE 0x80 	; # Initiate a new conversion(One-Shot Conversion mode only)

	set CMD_CHANNEL_MASK 0x60
	set CMD_CHANNEL_OFFSET 5
	set CMD_CHANNEL_1 0x00 			; # Mux Channel-1
	set CMD_CHANNEL_2 0x20 			; # Mux Channel-2
	set CMD_CHANNEL_3 0x40 			; # Mux Channel-3
	set CMD_CHANNEL_4 0x60 			; # Mux Channel-4

	set CMD_MODE_MASK 0x10
	set CMD_MODE_CONTINUOUS 0x10 		; # Continuous Conversion Mode
	set CMD_MODE_ONESHOT 0x00 		; # One-Shot Conversion Mode

	set CMD_SPS_MASK 0x0C
	set CMD_SPS_240  0x00 			; # 240 SPS (12-bit)
	set CMD_SPS_60   0x04 			; # 60 SPS (14-bit)
	set CMD_SPS_15   0x08 			; # 15 SPS (16-bit)
	set CMD_SPS_3_75 0x0C 			; # 3.75 SPS (18-bit)

	set CMD_GAIN_MASK 0x03
	set CMD_GAIN_1 0x00 			; # PGA Gain = 1V/V
	set CMD_GAIN_2 0x01 			; # PGA Gain = 2V/V
	set CMD_GAIN_4 0x02 			; # PGA Gain = 4V/V
	set CMD_GAIN_8 0x03 			; # PGA Gain = 8V/V

	set REGISTER_CONFIG [expr {
	   $::i2c::MCP342x::CMD_MODE_CONTINUOUS | $::i2c::MCP342x::CMD_SPS_15 | $::i2c::MCP342x::CMD_GAIN_2
	}]


	set REGISTER_SELECT [subst { 
		$::i2c::MCP342x::CMD_CHANNEL_1
		$::i2c::MCP342x::CMD_CHANNEL_2
		$::i2c::MCP342x::CMD_CHANNEL_3
		$::i2c::MCP342x::CMD_CHANNEL_4
	}]

	oo::class create a2d {

		constructor { { b 1 } { a 0x68 } } {
			variable bus 	 $b
			variable address $a
			variable handle [twowire twowire $bus $address]
		}
		method close {} {
			variable handle
			close $handle
		}
		method config { {ch 1 } } {
			variable handle
			set register_config [expr { 
				([lindex $::i2c::MCP342x::REGISTER_SELECT $ch] | $::i2c::MCP342x::REGISTER_CONFIG) 
			}] 

			
			twowire writebyte $handle $register_config
		}

		method read { { ch {} } } {
			variable handle

			if { $ch ne "" } {
				[self] config $ch
                after 75
			}

			set register_config [expr { 
				([lindex $::i2c::MCP342x::REGISTER_SELECT $ch] | $::i2c::MCP342x::REGISTER_CONFIG) 
			}] 

			set value [swap [twowire readregword $handle $register_config]]
			
			if { $value > 32767 } {
				set value [expr {$value - 65535 }]
			}
			
			return $value
		}
	}
}

