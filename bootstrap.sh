#!/bin/bash
# 
# UI Setup 
#
#   Raspberry Pi Configuration --> System --> change hostname
#   Raspberry Pi Configuration --> Interfaces --> i2c
#   Raspberry Pi Configuration --> Interfaces --> serail
#   Raspberry Pi Configuration --> Interfaces --> no console

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

    for inf in enx usb wwan eth ; do
        chk=$(ip -br addr show | awk "/$inf/"' { print $1; exit }')
        if [ "$chk" = "" ] ; then
            continue
        fi

        echo cell-interface $chk 1>&2
        echo $chk
        exit
    done
}

case $CMD in 
    auth|config|copy|overlay|remote|setup|gitkeys|keys|reboot|restore|update|kiosk)
        if [ "$1" != "" ] ; then
            PI=$1; shift
            if [ "$PI" = "" ] ; then
                echo "remote pi nmae required" 1>&2
                exit 1
            fi
        else
            echo "remote pi nmae required" 1>&2
            exit 1
        fi
        ;;
esac

case $CMD in 
    auth)
        ssh-auth $PI
        ;;
    setup)
        $0 copy $PI

        $0 remote $PI cell-down

        $0 keys $PI
        $0 gitkeys $PI
        scp $HOME/.gitconfig    $PI:
        scp $HOME/.vimrc        $PI:
        ;;
    install)
        sudo apt -y upgrade
        sudo apt -y update
        sudo apt -y autoremove


        sudo apt -y install mosh
        sudo apt -y install vim
        sudo apt -y install screen
        sudo apt -y install i2c-tools
        sudo apt -y install chromium
        sudo apt -y install unclutter

        yes | sudo apt -y install iptables-persistent

        $0 i2c
        $0 tcl

        git config --global core.sshCommand "ssh -i ~/.ssh/twilight-park -F /dev/null"
        $0 tpwater
        $0 piio
        $0 wapp
        $0 jbr

        sudo apt -y autoremove
        ;;
    post)
        $0 cell-routes
        $0 firewall up
        $0 firewall save
        $0 crontab up
        $0 autostart
        $0 rc.local


        if [ ! -f $HOME/apikey ] ; then
            ./tpwater/share/scripts/apikey.sh > $HOME/apikey
        fi
        ;;

    config)
        $0 copy
        $0 remote $PI raspi-config
        ;;

    raspi-config)
        hostname=$1

        echo Setting Hostname $hostname 1>&2

        sudo raspi-config nonint do_hostname $hostname
        sudo raspi-config nonint do_i2c 1
        sudo raspi-config nonint do_serial 2
        ;;

    update-software)
        git config --global core.sshCommand "ssh -i ~/.ssh/twilight-park -F /dev/null"

        ( cd tpwater            
          git pull 
        )
        ( cd tpwater/pkg/jbr.tcl
          git pull 
          make install-links
        )
        ( cd tpwater/pkg/wapp
          git pull 
        )
        ;;

    wifi)
        password=$1
        sudo bash -c "wpa_passphrase springcottage $password >> /etc/wpa_supplicant/wpa_supplicant.conf"
        sudo cat /etc/wpa_supplicant/wpa_supplicant.conf
        ;;

    clear-log)
        rm tpwater/log/*
        ;;

    update)
        $0 overlay $PI down 
        $0 reboot $PI
        sleep 90

        $0 copy $PI
        $0 gitkeys $PI
        $0 remote $PI crontab down
        $0 remote $PI tpwater.sh kill
        $0 remote $PI clear-log
        $0 remote $PI rc.local 
        $0 remote $PI firewall up
        $0 remote $PI firewall save
        $0 remote $PI update-software

        $0 overlay $PI up

        $0 remote $PI clear-log
        $0 remote $PI crontab up
        $0 reboot $PI
        sleep 90
        ;;

    overlay)
        case $1 in
         up)    ssh $PI "sudo raspi-config nonint do_overlayfs 0" ;;
         down)  ssh $PI "sudo raspi-config nonint do_overlayfs 1" ;;
        esac
        ;;

    reboot)
        ssh -o "ServerAliveInterval 2" $PI "sudo reboot"
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
            echo interface $cell | tee -a $DHCPCDCONF
            echo metric 2000     | tee -a $DHCPCDCONF
        else
            echo metric already set
        fi
        ;;
    cell-routes)
        ( cd tpwater/client/scripts
          sudo cp dhcpcd.enter-hook /etc/dhcpcd.enter-hook
        )
        $0 cell-metric
        $0 cell-down
        $0 cell-up
        /usr/sbin/route -n
        ;;
    firewall)
        tpwater/client/scripts/firewall "$@"
        ;;
    crontab)
        case $1 in
          up) cat $HOME/tpwater/share/scripts/crontab | crontab ;;
          down) echo | crontab ;;
        esac
        crontab -l
        ;;
    rc.local)
        if [ "$(grep tpwater /etc/rc.local)" = "" ] ; then
            sudo sed -i "/^exit 0 *$/i sudo -u john /home/john/tpwater/tpwater.sh start" /etc/rc.local
        else
            echo "rc.local already set"
        fi
        ;;

    sudoers)
        ssh $PI "echo 'john ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/john; sudo chmod go-wr /etc/sudoers.d/john"
        ;;

    gitkeys)
        ssh $PI rm .ssh/config .ssh/john@rkroll.com*
        scp $HOME/.ssh/twilight-park $PI:.ssh/.
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
    autostart)
        mkdir -p .config/lxsession/LXDE-pi
        cp tpwater/client/scripts/autostart .config/lxsession/LXDE-pi/autostart 
        ;;

    tcl)
        sudo apt -y install tcl-dev
        sudo apt -y install tcllib
        sudo apt -y install tcl8.6-tdbc-sqlite3 
        ;;
    tpwater.sh)
        tpwater/tpwater.sh "$@"
        ;;
    tpwater)
        git clone git@github.com:jbroll/tpwater.git
        ( cd tpwater
          git checkout rev2
        )
        ;;
    jbr)
        mkdir -p  $HOME/tpwater/pkg
        cd $HOME/tpwater/pkg

        git clone git@github.com:jbroll/jbr.tcl.git
        ( cd jbr.tcl

          ./configure 
          make install-links
        )
        ;;
    wapp)
        mkdir -p  $HOME/tpwater/pkg
        cd $HOME/tpwater/pkg

        git clone git@github.com:jbroll/wapp.git
	;;
    piio)
        mkdir -p  $HOME/tpwater/pkg
        cd $HOME/tpwater/pkg

        sudo apt -y install fossil
        fossil clone http://chiselapp.com/user/schelte/repository/piio
        sudo apt -y install tcl-dev libi2c-dev autoconf
        cd piio
        autoconf
        ./configure --prefix=$HOME/lib/tcl8 --exec_prefix=$HOME/lib/tcl8
        # ./configure --prefix=$HOME/lib/tcl8/site-tcl --exec_prefix=$HOME/lib/tcl8/site-tcl
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

    kiosk)
        $0 overlay $PI down 
        $0 reboot $PI
        sleep 90

        ssh $PI mkdir -p .config/lxsession/LXDE-pi
        scp kiosk/autostart $PI:.config/lxsession/LXDE-pi/autostart
        #ssh $PI sudo apt update
        #ssh $PI sudo apt upgrade -y
        #ssh $PI sudo apt install mosh -y
        #ssh $PI sudo apt install unclutter -y
        ssh $PI sudo apt install iotop -y
        #$0 overlay $PI up 
        #$0 reboot $PI
        ;;


    *)
        echo Huh? $0 "$@" 1>&2 
        ;;
esac

exit

	screen /dev/ttyUSB2 115200
    AT+CGDCONT?

    AT+CGDCONT=1,"IP","simbase"  # From Simbase Docs

RNDIS :
        AT+CUSBPIDSWITCH=9011,1,1
	back:
		AT+CUSBPIDSWITCH=9001,1,1

	AT+CRESET

Serail Number 	AT+CGSN

Status:
		AT+CPIN?
		AT+COPS?
		AT+CREG?
		AT+CPSI?

Time:
    AT+CTZU?
    AT+CTZU=1
    AT+CCLK?
