# Twilight Park Water System Monitor

A distributed monitoring system for water infrastructure including flow measurement, tank level monitoring, and remote pump control.

## System Architecture

The system consists of two main components:

### Hub Server
- Central data collection and storage server
- Web interface for monitoring and control
- SMS notification system for alerts
- Database storage for historical data
- Runs on `data.rkroll.com`

### Client Devices
- Raspberry Pi-based monitoring stations
- Analog sensor interfaces (pressure transducers, flow meters)
- GPIO control for pump relays
- Cellular modem connectivity for remote locations
- Local web interface for status display

## Hardware Configuration

### Supported Sensors
- **MCP342x**: 16-bit I2C ADC for analog sensors
- **ADS1115**: 16-bit I2C ADC (alternative)
- **GPIO**: Digital I/O for pump control

### Station Configurations

#### Waterplant Station
- Tank level monitoring (0-105% scale)
- Flow rate monitoring (0-50 GPM scale)
- MCP342x ADC on I2C address 0x68

#### Golf Course Station
- Pump control relay (GPIO pin 1)
- Current monitoring via MCP342x

#### Third Level Station
- Pump control relay (GPIO pin 1)
- Current monitoring via MCP342x

## Software Components

### Core Technologies
- **Tcl 8.6**: Primary programming language
- **SQLite**: Database for historical data
- **Wapp**: Web application framework
- **jbr::msg**: Message passing system for client-server communication

### Key Features
- Real-time data collection (20-second intervals)
- Web-based monitoring dashboard
- Automatic pump control based on tank levels
- Leak detection with SMS alerts
- Historical data visualization
- Multi-station support with unique API keys

## Installation

### Prerequisites
- Raspberry Pi running Raspbian
- I2C enabled in raspi-config
- Serial port enabled (for cellular modem)
- Network connectivity (WiFi or cellular)

### Bootstrap Process

1. Run the bootstrap script on a new Raspberry Pi:
```bash
./bootstrap.sh setup <pi-hostname>
```

2. The bootstrap script will:
   - Configure system settings
   - Install required packages
   - Set up I2C and GPIO interfaces
   - Configure cellular modem routing
   - Install the monitoring software

### Manual Installation Steps

1. Enable I2C:
```bash
sudo raspi-config nonint do_i2c 1
```

2. Install dependencies:
```bash
sudo apt install tcl-dev tcllib tcl8.6-tdbc-sqlite3 i2c-tools
```

3. Clone the repository:
```bash
git clone git@github.com:jbroll/tpwater.git
cd tpwater
```

4. Generate an API key for the station:
```bash
./share/scripts/apikey.sh > ~/apikey
```

5. Configure the station in `share/config/` with the appropriate `.cfg` file

## Configuration

### Station Configuration Files

Configuration files are located in `share/config/` and define:
- API key for authentication
- Sensor definitions and scaling
- GPIO pin assignments
- Recording intervals

Example configuration:
```tcl
apikey e334135d45cf405c9944e1df4a8118427d47a11e
record { period 20000 }

tank { 
    device MCP342x bus 1 address 0x68 channel 0 mode in sample 1000    
    zero 6050 scale 0.00444545 min 0 max 105 precision 2
}
flow {
    device MCP342x bus 1 address 0x68 channel 1 mode in sample 1000
    zero 6362 scale 0.0126887 min 0 max 50 precision 2
}
```

### Hub Configuration

The hub configuration (`hub/hub.cfg`) defines:
- Web and message server ports
- Notification settings
- Known hosts and devices
- Alert thresholds

## Operation

### Starting the System

Start the monitoring service:
```bash
./tpwater.sh start
```

Other commands:
- `./tpwater.sh stop` - Stop the service
- `./tpwater.sh restart` - Restart the service
- `./tpwater.sh stat` - Check service status
- `./tpwater.sh tail` - View live logs

### Automatic Startup

The system uses crontab for automatic startup:
```bash
*/2 * * * * /home/john/tpwater/tpwater.sh start
```

### Web Interface

Access the monitoring interface at:
- Hub: `http://data.rkroll.com:7777/monitor`
- Local station: `http://localhost:7777/status`

Available pages:
- `/monitor` - Main monitoring dashboard with charts
- `/status` - Simple status display
- `/connections` - View connected stations
- `/login` - Authentication page

## Alert System

### Leak Detection
- Monitors 10-minute rolling average flow rate
- Triggers SMS alert if flow exceeds threshold (default: 30 GPM)
- Rate-limited to prevent alert spam

### Weekly Test Notifications
- Sends test message every Monday at 10:05 AM
- Ensures notification system remains functional

### SMS Configuration
Uses Twilio for SMS notifications. Requires environment variables:
- Phone numbers and API credentials stored in `~/.twillio`

## Data Management

### Database Schema
- `waterplant` - Flow and tank measurements
- `golfcourse` - Pump status and current
- `thirdlevel` - Pump status and current
- `radio` - Cellular connection quality

### Backup System
Automated backups to remote server:
```bash
./tpwater.sh backup
```

Uses `pp-back` (Push/Pull Backup) system with incremental backups.

## Network Configuration

### Cellular Modem Setup
- Supports Quectel modems (via /dev/ttyUSB2)
- Automatic route configuration for dual connectivity
- Firewall rules to restrict cellular data usage

### Firewall Rules
Cellular interface restricted to:
- DNS (port 53)
- Data server (ports 8000, 8001)
- All other traffic blocked

## Troubleshooting

### Common Issues

1. **No sensor readings**
   - Check I2C connections: `i2cdetect -y 1`
   - Verify sensor addresses in configuration
   - Check power to sensors

2. **Communication failures**
   - Verify API key matches hub configuration
   - Check network connectivity
   - Review firewall settings

3. **Pump control issues**
   - Verify GPIO pin assignments
   - Check relay wiring
   - Monitor GPIO state in logs

### Log Files
Logs are stored in `log/` directory:
- `YYYYMMDD-tpwater-client.log` - Client station logs
- `YYYYMMDD-tpwater-hub.log` - Hub server logs

### Diagnostic Commands
```bash
# Check I2C devices
i2cdetect -y 1

# Monitor cellular signal
./client/sim-status.tcl

# Test sensor readings
tclsh
source client/devices/MCP342x.tcl
set adc [::i2c::MCP342x::a2d new 1 0x68]
$adc read 0
```

## Security

- API key authentication for all client connections
- Password-protected web interface
- Restricted cellular data usage via iptables
- No sensitive data stored on client devices

## Maintenance

### Regular Tasks
- Monitor log file sizes (auto-cleaned after 7 days)
- Check cellular data usage
- Verify sensor calibration
- Test notification system weekly

### Sensor Calibration
Adjust zero and scale values in configuration:
- `zero`: ADC reading at zero flow/pressure
- `scale`: Conversion factor to engineering units
- `min`/`max`: Valid range limits

## License

MIT
