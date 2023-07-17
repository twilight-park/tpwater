#!/bin/bash
# 

if [ "$1" != "" ] ; then
    CMD=$1; shift
else
    echo "usage: bootstrap.sh <pi> <command>" 1>&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

cell_interface() {
    #!/bin/sh
    #

    for inf in enx usb eth ; do
        chk=$(ip -br addr show | awk "/$inf/"' { print $1; exit }')
        if [ "$chk" = "" ] ; then
            continue
        fi

        echo $chk
        exit
    done
}

case $CMD in 
    auth|copy|remote|setup|keys|restore)
        if [ "$1" != "" ] ; then
            PI=$1; shift
        fi
        ;;
esac


case $CMD in 
    auth)
        $0 auth $PI
        ;;
    setup)
        $0 copy $PI

        $0 remote $PI cell-down
        $0 remote $PI cell-metric

        $0 remote $PI install

        $0 remote $PI cell-routes

        ssh $PI ./scripts/firewall up
        ssh $PI ./scripts/routes wifi

        $0 $PI keys
        $0 $PI restore

        yes | $0 $PI remote $PI install
        ssh $PI ./routes cell

        ssh $PI sudo ldto enable i2c-ao
        ;;

    copy)
        scp $0 $PI:
        ;;

    cell-down)
        cell=$(cell_interface)
        sudo ip link set $cell down
        sleep 2
        ;;
    cell-up)
        cell=$(cell_interface)
        sudo ip link set $cell up
        sleep 10
        route -n
        ;;
    cell-metric)
        cell=$(cell_interface)

        DHCPCDCONF=/etc/dhcpcd.conf
        done=$(grep "metric 2000" $DHCPCDCONF)

        if [ "$done" = "" ] ; then
            echo setting metric
            echo interface $cell | ssh $PI tee -a $DHCPCDCONF
            echo metric 2000    | ssh $PI tee -a $DHCPCDCONF
        fi
        echo metric already set
        ;;
    cell-routes)
        cd tpwater/client/scripts

        sudo cp dhcpcd.enter-hook /etc/dhcpcd.enter-hook
        $0 cell-down
        $0 cell-up
        /usr/sbin/route -n
        ;;
    sudoers)
        ssh $PI "echo 'john ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/john; sudo chmod go-wr /etc/sudoers.d/john"
        ;;
    keys)
        ssh $PI bash -c "
            cd .ssh; 
            rm id_rsa; 
            echo '' | ssh-keygen -t rsa -b 4096 -C $PI -f id_rsa -N ''
        "
        ssh $PI 'cat ~/.ssh/id_rsa.pub' | ssh-auth - data
        ;;
    copy)
        scp $0 $PI:
        ;;
    remote)
        ssh $PI ./bootstrap.sh "$@"
        ;;
    install)
        sudo apt -y upgrade
        sudo apt -y update
        sudo apt -y autoremove

        sudo apt -y install unclutter
        sudo apt -y install chromium

        sudo apt -y install mosh
        sudo apt -y install screen
        sudo apt -y install i2c-tools

        yes | sudo apt -y install iptables-persistent

        $0 i2c
        $0 tcl

        $0 tpwater
        $0 piio
        $0 jbr
        ;;

    autostart)
        mkdir -p .config/lxsession/LXDE-pi
        cp tpwater/client/scripts//autostart .config/lxsession/LXDE-pi/autostart 
        ;;

    tcl)
        sudo apt -y install tcl-dev
        sudo apt -y install tcllib
        sudo apt -y install tcl8.6-tdbc-sqlite3 
        ;;
    tpwater)
        git clone git@github.com:jbroll/tpwater.git
        ;;
    jbr)
        mkdir -p  $HOME/tpwater/pkg
        cd $HOME/tpwater/pkg

        git clone git@github.com:jbroll/jbr.tcl.git
        cd jbr.tcl

        ./configure 
        make install-links
        ;;
    piio)
        mkdir -p  $HOME/tpwater/pkg
        cd $HOME/tpwater/pkg

        sudo apt -y install fossil
        fossil clone http://chiselapp.com/user/schelte/repository/piio
        sudo apt -y install tcl-dev libi2c-dev autoconf
        cd piio
        autoconf
        ./configure --prefix=$HOME/lib/tcl8/site-tcl --exec_prefix=$HOME/lib/tcl8/site-tcl
        make
        make install
        ;;
    restore)
        FROM=raspberrypi

        if [ "$1" != "" ] ; then
            FROM=$1
        fi
        LATEST=$(ssh data ls -tr backups/raspberrypi | tail -1)
        ssh data tar cf - -C backups/$FROM/$LATEST . | ssh $PI tar xvf -
        ;;
esac

exit

qmi:
	sudo apt -y update && sudo apt -y install libqmi-utils udhcpc

	# Turn Radio on - not necessary?
	sudo qmicli -d /dev/cdc-wdm0 --dms-set-operating-mode='online'

	# Check Radio On
	sudo qmicli -d /dev/cdc-wdm0 --dms-get-operating-mode
	sudo qmicli -d /dev/cdc-wdm0 --nas-get-signal-strength
	sudo qmicli -d /dev/cdc-wdm0 --nas-get-home-network

	sudo qmicli -d /dev/cdc-wdm0 -w		# this confirms the name of the network interface, typically wwan0
	sudo ip link set wwan0 down		# change the wwan0 to the one returned above if different
	echo 'Y' | sudo tee /sys/class/net/wwan0/qmi/raw_ip
	sudo ip link set wwan0 up

	# Start network -- Running this once might have set the APN?
	#
	sudo qmicli -p -d /dev/cdc-wdm0 			\
	    --device-open-net='net-raw-ip|net-no-qos-header' 	\
	    --wds-start-network="apn='simbase',ip-type=4" --client-no-release-cid
	sudo udhcpc -i wwan0



	screen /dev/ttyUSB2 115200
	
Serail Number 	AT+CGSN

Set APN		AT+CGDCONT=1,"IP","simbase","0.0.0.0",0,0
		AT+CGDCONT=?
		AT+CGDCONT=1,"IP","simbase"
		AT+CGDCONT=1,"IPV4V6","simbase"
		AT+CGDCONT=6,"IPV4V6","simbase"


        AT+CGDCONT=1,"IP","simbase"  # From Simbase Docs


Reset		AT+CRESET


Status:
		AT+CPIN?
		AT+COPS?
		AT+CREG?
		AT+CPSI?

RNDIS : 	AT+CUSBPIDSWITCH=9011,1,1
	back:
		AT+CUSBPIDSWITCH=9001,1,1

	
	ping -I usb0 www.baidu.com
	sudo route add -net 0.0.0.0 usb0


i2c
	sudo mv /boot/dtb/amlogic/overlay/meson-i2cB.dtbo .
	sudo mv /boot/dtb/amlogic/overlay/meson-i2cA.dtbo .
	reboot
		
    sudo i2cdetect -y 1
	 0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
    00:                         -- -- -- -- -- -- -- --
    10: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
    20: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
    30: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
    40: -- -- -- -- -- -- -- -- 48 -- -- -- -- -- -- --
    50: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
    60: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
    70: -- -- -- -- -- -- -- --

i2c Python

	sudo apt -y install build-essential libi2c-dev i2c-tools python-dev libffi-dev
	sudo apt -y install pip
	pip install cffi
	pip install smbus-cffi

	get clone
	python3 Example...


To Try:
	armbian-add-overlay i2c-b.dts

