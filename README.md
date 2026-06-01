# Twilight Park Water System Monitor

A distributed monitoring system for water infrastructure including flow measurement, tank level monitoring, and remote pump control.

## Table of Contents
- [System Architecture](#system-architecture)
- [Hardware Configuration](#hardware-configuration)
- [Software Components](#software-components)
- [Installation](#installation)
- [Configuration](#configuration)
- [Operation](#operation)
- [Alert System](#alert-system)
- [Data Management](#data-management)
- [Network Configuration](#network-configuration)
- [Troubleshooting](#troubleshooting)
- [Security](#security)
- [Maintenance](#maintenance)
- [Technical Deep Dive](#technical-deep-dive)
  - [Software Architecture Details](#software-architecture-details)
  - [Message System Architecture](#message-system-architecture)
  - [Web Interface Architecture](#web-interface-architecture)
  - [Advanced Features](#advanced-features)
  - [Development Guidelines](#development-guidelines)

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

#### Test Card
- Analog input monitoring
- GPIO output control
- Used for system testing and development

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
git clone git@github.com:twilight-park/tpwater.git
cd tpwater
git checkout main
```

4. Generate an API key for the station:
```bash
./share/scripts/apikey.sh > ~/apikey
```

5. Configure the station in `share/config/` with the appropriate `.cfg` file

6. Set up automatic startup:
```bash
./tpwater.sh crontab
```

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

### Sensor Calibration Parameters
- `zero`: ADC reading at zero flow/pressure
- `scale`: Conversion factor to engineering units
- `min`/`max`: Valid range limits
- `precision`: Decimal places for display
- `sample`: Averaging time in milliseconds

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
- `./tpwater.sh retail` - Restart and tail logs

### Automatic Startup

The system uses crontab for automatic startup:
```bash
*/2 * * * * /home/john/tpwater/tpwater.sh start
45  2 * * * /home/john/tpwater/tpwater.sh restart
50  2 * * * find /home/john/tpwater/log -type f -mtime +7 -delete
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
- `/m2` - Mobile-optimized interface

### Kiosk Mode

For dedicated display terminals:
```bash
./bootstrap.sh kiosk <pi-hostname>
```

This configures a Raspberry Pi to automatically display the monitoring interface on boot.

## Alert System

### Leak Detection
- Monitors 10-minute rolling average flow rate
- Triggers SMS alert if flow exceeds threshold (default: 30 GPM)
- Rate-limited to prevent alert spam (6-hour minimum between alerts)

### Weekly Test Notifications
- Sends test message every Monday at 10:05 AM
- Ensures notification system remains functional

### SMS Configuration
Uses Twilio for SMS notifications. Requires environment variables:
- Phone numbers and API credentials stored in `~/.twillio`
- Contact information configured in hub environment

### Alert Types
- **LEAK**: High flow rate detection
- **NOTE**: Weekly system test
- Additional alerts can be configured in `hub/rules.tcl`

## Data Management

### Database Schema
- `waterplant` - Flow and tank measurements
- `golfcourse` - Pump status and current
- `thirdlevel` - Pump status and current
- `radio` - Cellular connection quality
- `config` - System configuration storage

### Data Collection
- Measurements taken every 20 seconds
- Local averaging for noise reduction
- Automatic time synchronization
- Duplicate detection and handling

### Backup System
Automated backups to remote server:
```bash
./tpwater.sh backup
```

Uses `pp-back` (Push/Pull Backup) system with:
- Incremental backups using rsync
- 30-day retention for daily backups
- Permanent monthly backups (1st of each month)
- Automatic cleanup of old backups

### Data Queries
Query historical data:
```bash
./query.tcl tpwater.db waterplant -1d now
```

## Network Configuration

### Cellular Modem Setup
- Supports Quectel modems (via /dev/ttyUSB2)
- Automatic route configuration for dual connectivity
- Signal strength monitoring
- Network operator selection

### AT Commands for Modem Configuration

Connect to the modem console:
```bash
screen /dev/ttyUSB2 115200   # CTRL-A \ to exit
```

```
# Status
AT+CSQ                       # Signal strength
AT+CREG?                     # Network registration
AT+COPS?                     # Current operator
AT+CPSI?                     # Detailed network info (band, cell, RSRP, etc.)
AT+CGSN                      # Serial number

# APN
AT+CGDCONT?                  # Check APN settings
AT+CGDCONT=1,"IP","simbase"  # Set APN (Simbase)

# Network operator
AT+COPS=?                    # Scan available operators
AT+COPS=0                    # Auto-select operator
AT+COPS=1,2,"310410"         # Force AT&T
AT+COPS=1,2,"310260"         # Force T-Mobile

# USB networking mode (requires AT+CRESET after change)
AT+CUSBPIDSWITCH=9011,1,1    # Switch to RNDIS mode
AT+CUSBPIDSWITCH=9001,1,1    # Switch back to ECM mode

# Time sync
AT+CTZU?                     # Check auto time zone update
AT+CTZU=1                    # Enable auto time zone update
AT+CCLK?                     # Check modem clock

# Reset
AT+CRESET                    # Reset modem
```

### Firewall Rules
Cellular interface restricted to:
- DNS (port 53)
- Data server (ports 8000, 8001)
- All other traffic blocked

Apply firewall rules:
```bash
./client/scripts/firewall up
./client/scripts/firewall save
```

### Route Management
The system automatically manages routes:
- WiFi preferred for general traffic
- Cellular used for critical data uploads
- Automatic failover on connection loss

## Troubleshooting

### Common Issues

1. **No sensor readings**
   - Check I2C connections: `i2cdetect -y 1`
   - Verify sensor addresses in configuration
   - Check power to sensors (3.3V or 5V as required)

2. **Communication failures**
   - Verify API key matches hub configuration
   - Check network connectivity: `ping data.rkroll.com`
   - Review firewall settings: `sudo iptables-save`

3. **Pump control issues**
   - Verify GPIO pin assignments
   - Check relay wiring and power supply
   - Monitor GPIO state in logs
   - Test manual control via web interface

4. **Cellular connection problems**
   - Check SIM card installation
   - Verify APN settings: `AT+CGDCONT?`
   - Monitor signal strength
   - Check data plan status

### Log Files
Logs are stored in `log/` directory:
- `YYYYMMDD-tpwater-client.log` - Client station logs
- `YYYYMMDD-tpwater-hub.log` - Hub server logs
- Automatic cleanup after 7 days

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

# Check message system connection
export MSGDEBUG=1
./tpwater.sh restart
```

## Security

- API key authentication for all client connections
- Password-protected web interface
- Restricted cellular data usage via iptables
- No sensitive data stored on client devices
- Access control lists for message server

### Password Management
Generate password hash:
```bash
echo -n "password" | md5sum
```

Add to password file:
```
<hash> control username
```

## Maintenance

### Regular Tasks
- Monitor log file sizes (auto-cleaned after 7 days)
- Check cellular data usage
- Verify sensor calibration quarterly
- Test notification system weekly
- Review and update firewall rules

### Sensor Calibration
1. Stop data collection: `./tpwater.sh stop`
2. Record zero point (no flow/empty tank)
3. Apply known reference (flow rate/tank level)
4. Calculate new zero and scale values
5. Update configuration file
6. Restart service: `./tpwater.sh start`

### System Updates
```bash
# Update software on client
./bootstrap.sh update <pi-hostname>

# Update software on hub
cd tpwater
git pull
./tpwater.sh restart
```

### Performance Monitoring
- Database size: `ls -lh tpwater.db`
- Message latency: Check timestamps in logs
- CPU usage: `top` or `htop`
- Network bandwidth: `iftop`

---

## Technical Deep Dive

The following sections provide detailed technical information for developers and advanced users.

### Software Architecture Details

#### Layered Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Web Interface Layer                    │
│  (Wapp Framework, HTTP Services, Real-time Updates)     │
├─────────────────────────────────────────────────────────┤
│                 Application Logic Layer                  │
│  (Rules Engine, Alert System, Data Processing)          │
├─────────────────────────────────────────────────────────┤
│                Message Communication Layer               │
│          (jbr::msg Pub/Sub, API Key Auth)              │
├─────────────────────────────────────────────────────────┤
│                   Data Storage Layer                     │
│        (SQLite, Time-series Data, Configuration)        │
├─────────────────────────────────────────────────────────┤
│                Hardware Abstraction Layer                │
│    (I2C Devices, GPIO, Sensor Scaling, Calibration)    │
└─────────────────────────────────────────────────────────┘
```

#### Design Patterns

**Object-Oriented Design**
The system uses Tcl's TclOO for hardware abstraction:

```tcl
oo::class create channel {
    variable config
    method scaled { value } {
        # Applies calibration and scaling
    }
    method config { c } {
        set config $c
    }
}

oo::class create dev-channel {
    superclass channel
    variable device channel sample value current
    # Extends channel with device-specific behavior
}
```

**Factory Pattern**
Device creation uses a factory-like approach:
```tcl
switch $device {
    ADS1115 -
    MCP342x {
        ::i2c::${device}::a2d create $dev $bus $address
    }
    gpio {
        gpio::gpio::gpio create $dev
    }
}
```

**Observer Pattern**
The pub/sub system implements observer pattern for state changes:
```tcl
msg_subscribe WATER $name:request {} "set-state $name"
```

### Message System Architecture

#### jbr::msg Pub/Sub System

The system uses a custom TCP-based pub/sub messaging system with these features:

**Message Flow**
```
Client Station                    Hub Server
     │                                │
     ├──[API Key Auth]───────────────>│
     │                                │
     ├──[Subscribe to controls]──────>│
     │                                │
     ├──[Publish sensor data]────────>│
     │                                │
     │<─────[Control commands]────────┤
     │                                │
     │<─────[Clock sync]──────────────┤
```

**Key Features**
- API Key Authentication: Each client has a unique key
- Automatic Reconnection: Handles network interruptions gracefully
- Keepalive Mechanism: Detects dead connections (5-60 second timeout)
- Asynchronous Operations: Non-blocking message delivery
- Topic-based Routing: Hierarchical topic structure

**Message Types**

1. Sensor Data Messages
   ```tcl
   msg_cmd WATER "rec [clock seconds] $values" 0 nowait
   ```

2. Control Messages
   ```tcl
   msg_set WATER $name:request $value {} async
   ```

3. State Synchronization
   ```tcl
   msg_publish WATER $name {} 
   msg_subscribe WATER $name
   ```

4. System Messages
   ```tcl
   msg_publish WATER clk  # Clock synchronization
   ```

### Web Interface Architecture

#### Frontend Technology Stack
- No Framework Dependency: Vanilla JavaScript for reliability
- Real-time Updates: Polling-based updates (5-second intervals)
- Responsive Design: Mobile-friendly layouts
- uPlot for high-performance time-series

#### Template System
Uses jbr::template for server-side rendering:
```tcl
template-environment create T
T macros $script_dir/../share/html
```

#### Dynamic Content Injection
```html
[< buttonState]  <!-- Macro inclusion -->
[!flow get max]  <!-- Variable substitution -->
[? [!is-localhost?] "" : { <!-- Conditional rendering -->
    <button onClick='logout()'>Logout</button>
}]
```

#### API Endpoints

**Data Query API**
```
GET /query/{table}/{start}/{end}
```
Returns time-series data with automatic minute-level aggregation

**Real-time Values API**
```
GET /values?page={page}
```
Returns current system state and sensor readings

**Control API**
```
GET /press?button={control_name}
```
Triggers pump control state changes

**Rolling Average API**
```
GET /query2/{lookback}/{window}/{frequency}
```
Returns processed flow data with rolling averages

**Client Status API**
```
GET /clients
```
Returns connected station information in JSON format

#### Client-Side Architecture

**State Management**
- Device UUID generation for tracking
- LocalStorage for persistent device ID
- Automatic page reload on configuration changes
- MD5 checksums for change detection

**Update Strategies**
```javascript
setInterval(() => { updatePage(); }, 5000);      // State updates
setInterval(() => { updateCharts(); }, 20000);   // Chart updates
setInterval(() => { reloadPage(); }, 86400000);  // Daily refresh
```

**Data Filtering**
The system includes spike filtering for noisy sensor data:
```javascript
function filterNoisySpikes(data, threshold = 35, windowSize = 10, 
                          minRemoveCount = 1, maxRemoveCount = 5, 
                          fallbackValue = null)
```

### Data Flow and Processing

#### Data Collection Pipeline

1. **Sensor Reading**
   ```
   Physical Sensor → ADC → I2C Read → Scaling → Averaging → Message Bus
   ```

2. **Data Processing**
   ```
   Message Receipt → Validation → Database Storage → State Update → Rule Evaluation
   ```

3. **Client Data Flow**
   ```tcl
   proc readout {} {
       foreach device $::devices {
           _sample $device {*}[dict get [set ::$device] channels]
       }
       every [dict get $::record period] "record {*}$::inputs"
   }
   ```

#### Time-Series Analysis

**Rolling GPM Calculation**
```tcl
proc rolling_gpm {db_connection table_name time_column flow_column 
                  lookback window frequency points} {
    # Calculates rolling average flow rate
    # Uses sliding window for anomaly detection
    # Requires minimum data points for validity
}
```

The algorithm:
1. Retrieves historical data within lookback period
2. Applies sliding window averaging
3. Enforces minimum data point requirements
4. Outputs at specified frequency intervals

#### State Persistence

**Hub State**
```tcl
proc save-state {} {
    echo [subst {
        set auto $::auto
    }] > $::script_dir/state.cfg
}
```

**Notification State**
Persisted to prevent duplicate alerts:
```tcl
set ::noted "LEAK 1749392885594 NOTE 1748873100412"
```

### Advanced Features

#### Coroutine-based Sampling
Enables non-blocking sensor reading:
```tcl
package require coroutine::auto

proc sample { device args } {
    [coroutine::util create apply {{device args} {
        yield [info coroutine]
        _sample $device {*}$args
    }} $device {*}$args]
}
```

#### Dynamic Configuration Loading
- Hot-reload of HTML templates via file watching
- Configuration change detection using MD5 checksums
- No service restart required for UI changes

#### Multi-Architecture Support
Automatic detection and loading of architecture-specific code:
```tcl
source $script_dir/devices/gpio-[run uname -m].tcl
```
Supports:
- armv7l (32-bit Raspberry Pi)
- aarch64 (64-bit Raspberry Pi)

#### Time Synchronization
- Hub broadcasts time via message bus
- Automatic client clock adjustment
- Reduces cellular data usage (no NTP)

#### Rules Engine

The system uses a flexible rules engine with cron-like scheduling:

```tcl
every 5000 {
    try-rule auto {
        if { $::tank <= 101.5 } {
            set ::golf:request 1
            set ::thrd:request 1
        }
        if { $::tank > 102.5 } {
            set ::golf:request 0
            set ::thrd:request 0
        }
    }
}

cron { every 2m at 5s } {
    try-rule LEAK {
        set rate 30
        set data [rolling_gpm db waterplant time_recorded flow 0 10.5m 1s 28]
        set f10w [flow scaled [lindex $data 0 1]]
        if { $f10w >= $rate } {
            notify LEAK rate $rate f10w $f10w
        }
    }
}
```

### Development Guidelines

#### Code Organization
- Modular design with clear separation of concerns
- Consistent naming conventions (snake_case for procs, camelCase for methods)
- Comprehensive error handling with try/on error blocks
- Logging at appropriate levels

#### Testing Approach
- Hardware abstraction allows unit testing
- Test card configuration for development
- Integration tests via message bus
- Simulation mode for sensor data

#### Extension Points
1. **New Sensor Types**: Add drivers in `client/devices/`
2. **Additional Rules**: Extend `hub/rules.tcl`
3. **Custom Notifications**: Modify `hub/notify.tcl`
4. **Alternative Storage**: Replace SQLite in `hub/db-setup.tcl`
5. **New Web Pages**: Add templates in `share/html/`

#### Performance Considerations
- Database queries use minute-level aggregation
- Client-side data filtering reduces noise
- Message batching minimizes network usage
- Efficient coroutine-based sampling

## License

MIT
