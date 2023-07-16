
package require TclOO
package require piio 1.2

proc swap { x } {
	return [expr { ( ($x & 0xFF00) >> 8 ) | ( ($x & 0x00FF) << 8 ) }]
}

# I2C address of the device
namespace eval ::i2c {}
namespace eval ::i2c::ADS1115 {
	set ADS1115_DEFAULT_ADDRESS		 0x48

	# Register Map
	set REG_POINTER_CONVERT		 0x00 ; # Conversion register
	set REG_POINTER_CONFIG		 0x01 ; # Configuration register
	set REG_POINTER_LOWTHRESH	 0x02 ; # Lo_thresh register
	set REG_POINTER_HITHRESH	 0x03 ; # Hi_thresh register

	# Configuration Register
	set REG_CONFIG_OS_NOEFFECT	 0x00 ; # No effect
	set REG_CONFIG_OS_SINGLE	 0x80 ; # Begin a single conversion
	set REG_CONFIG_MUX_DIFF_0_1	 0x00 ; # Differential P = AIN0, N = AIN1 (default)
	set REG_CONFIG_MUX_DIFF_0_3	 0x10 ; # Differential P = AIN0, N = AIN3
	set REG_CONFIG_MUX_DIFF_1_3	 0x20 ; # Differential P = AIN1, N = AIN3
	set REG_CONFIG_MUX_DIFF_2_3	 0x30 ; # Differential P = AIN2, N = AIN3
	set REG_CONFIG_MUX_SINGLE_0	 0x40 ; # Single-ended P = AIN0, N = GND
	set REG_CONFIG_MUX_SINGLE_1	 0x50 ; # Single-ended P = AIN1, N = GND
	set REG_CONFIG_MUX_SINGLE_2	 0x60 ; # Single-ended P = AIN2, N = GND
	set REG_CONFIG_MUX_SINGLE_3	 0x70 ; # Single-ended P = AIN3, N = GND
	set REG_CONFIG_PGA_6_144V	 0x00 ; # +/-6.144V range = Gain 2/3
	set REG_CONFIG_PGA_4_096V	 0x02 ; # +/-4.096V range = Gain 1
	set REG_CONFIG_PGA_2_048V	 0x04 ; # +/-2.048V range = Gain 2 (default)
	set REG_CONFIG_PGA_1_024V	 0x06 ; # +/-1.024V range = Gain 4
	set REG_CONFIG_PGA_0_512V	 0x08 ; # +/-0.512V range = Gain 8
	set REG_CONFIG_PGA_0_256V	 0x0A ; # +/-0.256V range = Gain 16
	set REG_CONFIG_MODE_CONTIN	 0x00 ; # Continuous conversion mode
	set REG_CONFIG_MODE_SINGLE	 0x01 ; # Power-down single-shot mode (default)
	set REG_CONFIG_DR_8SPS		 0x00 ; # 8 samples per second
	set REG_CONFIG_DR_16SPS		 0x20 ; # 16 samples per second
	set REG_CONFIG_DR_32SPS		 0x40 ; # 32 samples per second
	set REG_CONFIG_DR_64SPS		 0x60 ; # 64 samples per second
	set REG_CONFIG_DR_128SPS	 0x80 ; # 128 samples per second (default)
	set REG_CONFIG_DR_250SPS	 0xA0 ; # 250 samples per second
	set REG_CONFIG_DR_475SPS	 0xC0 ; # 475 samples per second
	set REG_CONFIG_DR_860SPS	 0xE0 ; # 860 samples per second
	set REG_CONFIG_CMODE_TRAD	 0x00 ; # Traditional comparator with hysteresis (default)
	set REG_CONFIG_CMODE_WINDOW	 0x10 ; # Window comparator
	set REG_CONFIG_CPOL_ACTVLOW	 0x00 ; # ALERT/RDY pin is low when active (default)
	set REG_CONFIG_CPOL_ACTVHI	 0x08 ; # ALERT/RDY pin is high when active
	set REG_CONFIG_CLAT_NONLAT	 0x00 ; # Non-latching comparator (default)
	set REG_CONFIG_CLAT_LATCH	 0x04 ; # Latching comparator
	set REG_CONFIG_CQUE_1CONV	 0x00 ; # Assert ALERT/RDY after one conversions
	set REG_CONFIG_CQUE_2CONV	 0x01 ; # Assert ALERT/RDY after two conversions
	set REG_CONFIG_CQUE_4CONV	 0x02 ; # Assert ALERT/RDY after four conversions
	set REG_CONFIG_CQUE_NONE	 0x03 ; # Disable the comparator and put ALERT/RDY in high state (default)

	set REGISTER_CONFIG_0 [expr { 
			$::i2c::ADS1115::REG_CONFIG_OS_SINGLE | 
			$::i2c::ADS1115::REG_CONFIG_MUX_SINGLE_0 | 
			$::i2c::ADS1115::REG_CONFIG_PGA_2_048V | 
			$::i2c::ADS1115::REG_CONFIG_MODE_CONTIN 
		}] 
	set REGISTER_CONFIG_1 [expr { $::i2c::ADS1115::REG_CONFIG_DR_128SPS | $::i2c::ADS1115::REG_CONFIG_CQUE_NONE }]
	set REGISTER_SELECT [subst {
		{}
		{ $::i2c::ADS1115::REG_CONFIG_MUX_SINGLE_0
		  $::i2c::ADS1115::REG_CONFIG_MUX_SINGLE_1
		  $::i2c::ADS1115::REG_CONFIG_MUX_SINGLE_2
		  $::i2c::ADS1115::REG_CONFIG_MUX_SINGLE_3
		}
		{
		  $::i2c::ADS1115::REG_CONFIG_MUX_DIFF_0_1	
		  $::i2c::ADS1115::REG_CONFIG_MUX_DIFF_0_3
		  $::i2c::ADS1115::REG_CONFIG_MUX_DIFF_1_3
		  $::i2c::ADS1115::REG_CONFIG_MUX_DIFF_2_3
		}
	}]

	oo::class create a2d {

		constructor { { b 1 } { a 0x48 } } {
			variable bus 	 $b
			variable address $a
			variable handle [twowire twowire $bus $address]
		}
		method close {} {
			variable handle
			close $handle
		}
		method config { { c 0 } { e 1 } } {
			variable handle
			set register_config [expr { 
				([lindex $::i2c::ADS1115::REGISTER_SELECT $e $c] | $::i2c::ADS1115::REGISTER_CONFIG_0)  |
				( $::i2c::ADS1115::REGISTER_CONFIG_1 << 8 )
			}] 

			twowire writeregword $handle $::i2c::ADS1115::REG_POINTER_CONFIG $register_config
		}

		method read { { ch {} } } {
			variable handle

			if { $ch ne "" } {
				[self] config $ch
				after 80
			}

			set value [swap [twowire readregword $handle $::i2c::ADS1115::REG_POINTER_CONVERT]]
			
			if { $value > 32767 } {
				set value [expr {$value - 65535 }]
			}
			
			return $value
		}
	}
}

