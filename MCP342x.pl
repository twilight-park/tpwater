

import smbus2

# I2C address of the device
set DEFAULT_ADDRESS = 0x68
set REFERENCE_VOLTAGE = 2.048

# MCP3425/6/7/8 Configuration Command Set
set CMD_CONVERSION_MASK = 0x80
set CMD_CONVERSION_READY = 0x00 # Conversion Complete: 0=data ready, 1=not_finished.
set CMD_CONVERSION_INITIATE = 0x80 # Initiate a new conversion(One-Shot Conversion mode only)

set CMD_CHANNEL_MASK = 0x60
set CMD_CHANNEL_OFFSET = 5
set CMD_CHANNEL_1 = 0x00 # Mux Channel-1
set CMD_CHANNEL_2 = 0x20 # Mux Channel-2
set CMD_CHANNEL_3 = 0x40 # Mux Channel-3
set CMD_CHANNEL_4 = 0x60 # Mux Channel-4

set CMD_MODE_MASK = 0x10
set CMD_MODE_CONTINUOUS = 0x10 # Continuous Conversion Mode
set CMD_MODE_ONESHOT = 0x00 # One-Shot Conversion Mode

set CMD_SPS_MASK = 0x0C
set CMD_SPS_240 = 0x00 # 240 SPS (12-bit)
set CMD_SPS_60 = 0x04 # 60 SPS (14-bit)
set CMD_SPS_15 = 0x08 # 15 SPS (16-bit)
set CMD_SPS_3_75 = 0x0C # 3.75 SPS (18-bit)

set CMD_GAIN_MASK = 0x03
set CMD_GAIN_1 = 0x00 # PGA Gain = 1V/V
set CMD_GAIN_2 = 0x01 # PGA Gain = 2V/V
set CMD_GAIN_4 = 0x02 # PGA Gain = 4V/V
set CMD_GAIN_8 = 0x03 # PGA Gain = 8V/V

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
				(
				    [lindex $::i2c::ADS1115::REGISTER_SELECT $e $c] 
				  | $::i2c::ADS1115::REGISTER_CONFIG_0
				)  |
				( $::i2c::ADS1115::REGISTER_CONFIG_1 << 8 )
			}] 

			twowire writeregword $handle $::i2c::ADS1115::REG_POINTER_CONFIG $register_config
		}

		method read { { ch {} } } {
			variable handle

			if { $ch ne "" } {
				[self] config $ch
				after 250
			}

			set value [swap [twowire readregword $handle $::i2c::ADS1115::REG_POINTER_CONVERT]]
			
			if { $value > 32767 } {
				set value [expr {$value - 65535 }]
			}
			
			return $value
		}
	}
}
class Channel(object):
    '''access a/d device through a channel object'''
    def __init__(self, device, channel_number):
        '''
        channel mixin. non variety specific routines for channel.
        device is an initialized mcp342x instance
        channel_number is the zero referenced mux channel number to access
        '''

        #create out local variables
        super().__setattr__("_device", None)
        super().__setattr__("_config", None)
        super().__setattr__("_channel_number", None)
        super().__setattr__("_pga_gain", None)
        super().__setattr__("_sample_rate", None)
        super().__setattr__("_max_code", None)

        self._config = 0

        self._device = device
        self.number = channel_number
        
        self.pga_gain = 1
        self.sample_rate = 240
        self.continuous = True
        return

    @property
    def config(self):
        '''peek into current config settings for this channel.  for help in debug'''
        return self._config

    @property
    def is_active(self):
        '''returns true if the mux is set to this channel'''
        return self._device.active_channel == self._channel_number

    @property
    def number(self):
        ''' returns the zero referenced mux channel this object controls'''
        return self._channel_number

    @number.setter
    def number(self, channel_number):
        ''' sets the mux channel for this object.'''

        # verify number is valid for this adc 
        self._device.validate_channel_number(channel_number)

        # validate_channel raises bad value.  must be ok...
        self._config &= ~CMD_CHANNEL_MASK
        if channel_number == 0:
            self._config |= CMD_CHANNEL_1
        elif channel_number == 1:
            self._config |= CMD_CHANNEL_2
        elif channel_number == 2:
            self._config |= CMD_CHANNEL_3
        elif channel_number == 3:
            self._config |= CMD_CHANNEL_4
            
        self._channel_number = channel_number
        return

    @property
    def sample_rate(self):
        ''' returns channel sample rate in samples per second'''
        return self._sample_rate

    @sample_rate.setter
    def sample_rate(self, rate):
        ''' sets channel sample rate: 240, 60, or 15 sps'''
        self._config &= ~CMD_SPS_MASK
        if rate == 15:
            self._config |= CMD_SPS_15
            self._max_code = 32767
        elif rate == 60:
            self._config |= CMD_SPS_60
            self._max_code = 8191
        elif rate == 240:
            self._config |= CMD_SPS_240
            self._max_code = 2047
        else:
            raise ValueError('Possible sample_rate settings are 15, 60, or 240 samples per second')
        self._sample_rate = rate
        return

    @property
    def pga_gain(self):
        ''' returns pga gain: 1, 2, 4, or 8'''
        return self._pga_gain

    @pga_gain.setter
    def pga_gain(self, gain):
        ''' sets pga gain for this channel: 1, 2, 4, or 8'''
        self._config &= ~CMD_GAIN_MASK
        if gain == 1:
            self._config |= CMD_GAIN_1
        elif gain == 2:
            self._config |= CMD_GAIN_2
        elif gain == 4:
            self._config |= CMD_GAIN_4
        elif gain == 8:
            self._config |= CMD_GAIN_8
        else:
            raise ValueError('Possible pga gain settings are 1, 2, 4, or 8')
        self._pga_gain = gain
        return

    @property
    def max_voltage(self):
        ''' returns the maximum usable input in volts for this channel '''
        return REFERENCE_VOLTAGE / self._pga_gain

    @property
    def lsb_voltage(self):
        ''' returns the resolution in volts for this channel '''
        return self.max_voltage / self._max_code

    @property
    def continuous(self):
        ''' returns true if current channel conversion mode is continuous, false if one-shot'''
        status = False
        if self._config & CMD_MODE_CONTINUOUS:
            status = True
        return status

    @continuous.setter
    def continuous(self, enabled):
        ''' sets channel conversion mode to continuous, false for one-shot'''
        self._config &= ~CMD_MODE_CONTINUOUS
        if enabled is True:
            self._config |= CMD_MODE_CONTINUOUS
        return

    @property
    def conversion_time(self):
        '''
        return estimated time in seconds to complete a single conversion
        assuming its present configuration
        '''
        return 1/self._sample_rate

    def start_conversion(self):
        '''
        Update device config register with our parameters and start conversion.
        If channel configured for continuous mode, conversions continue automatically
        If channel configured for one-shot mode (ie not continuous),
        trigger a single conversion and allow chip to enter low power mode.
        '''
        self._device.initiate_conversion(self._config)

        return True

    def get_conversion_raw(self):
        ''' returns the latest conversion in semi raw two's complement binary'''
        not_ready, raw = self._device.get_conversion(self._sample_rate)
        if not_ready:
            raise ConversionNotReadyError

        return raw

    def get_conversion_volts(self):
        ''' returns the latest conversion in Volts with pga settings applied'''
        raw_value = self.get_conversion_raw()
        volts = raw_value * self.lsb_voltage
        return volts

class Mcp342x(object):
    ''' hardware access to the chip'''
    def __init__(self, bus, address=DEFAULT_ADDRESS):
        '''bus is integer id of i2c bus, address is integer address of chip on that bus'''
        self._bus = smbus2.SMBus(bus)
        self._address = address
        self._config_cache = 0
        return

    @property
    def active_channel(self):
        ''' returns the current mux channel setting'''
        return (self._config_cache & CMD_CHANNEL_MASK) >> CMD_CHANNEL_OFFSET

    def validate_channel_number(self, channel_number):
        ''' overide with your adc's channel validation check. Raise ValueError if out of bounds '''
        ''' validates the mux channel for this version adc.'''
        return
    
    def initiate_conversion(self, config):
        ''' send conversion initiate command'''
        self._config_cache = config

        try:
            self._bus.write_byte(self._address, self._config_cache | CMD_CONVERSION_INITIATE)
        except OSError as e:
            if e.errno == 121: #Remote I/O error
                raise I2CBussError
            else:
                raise

        return True

    def get_conversion(self, rate):
        ''' get conversion if ready'''
        raw_adc = 0

        try:
            data = self._bus.read_i2c_block_data(self._address, self._config_cache, 3)
        except OSError as e:
            if e.errno == 121:
                raise I2CBussError
            else:
                raise

        status = data[2]
        if (status & CMD_CONVERSION_MASK) == CMD_CONVERSION_READY:
            not_ready = False
            #print('status={:0b}, data0={:0x}, data1={:0x}'.format(status, data[0], data[1]))
            if rate == 240:
                raw_adc = ((data[0] & 0x0F) * 256) + data[1]
                if raw_adc > 2047:
                    raw_adc -= 4096
            elif rate == 60:
                raw_adc = ((data[0] & 0x3F) * 256) + data[1]
                if raw_adc > 8191:
                    raw_adc -= 16384
            elif rate == 15:
                raw_adc = (data[0] * 256) + data[1]
                if raw_adc > 32767:
                    raw_adc -= 65536
            else:
                pass
        else:
            not_ready = True

        return not_ready, raw_adc

class Mcp3425(Mcp342x):
    '''MCP3425 specific channel parameters'''

    def validate_channel_number(self, channel_number):
        ''' validates the mux channel for this version adc.'''
        if channel_number != 0:
            raise ValueError('Possible MCP3425 channel numbers are 0')
        return

class Mcp3426(Mcp342x):
    '''MCP3426 specific channel parameters'''

    def validate_channel_number(self, channel_number):
        ''' validates the mux channel for this version adc.'''
        if not 0 < channel_number < 2:
            raise ValueError('Possible MCP3426 channel numbers are 0 and 1')
        return

class Mcp3427(Mcp342x):
    '''MCP3427 specific channel parameters (electrically same as the mcp3426, different package)'''

    def validate_channel_number(self, channel_number):
        ''' validates the mux channel for this version adc.'''
        if not 0 <= channel_number < 2:
            raise ValueError('Possible MCP3427 channel numbers are 0 and 1')
        return

class Mcp3428(Mcp342x):
    '''MCP3428 specific channel parameters'''

    def validate_channel_number(self, channel_number):
        ''' validates the mux channel for this version adc.'''
        if not 0 <= channel_number < 4:
            raise ValueError('Possible MCP3428 channel numbers are 0, 1, 2, and 3')
        return
