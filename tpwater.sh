#!/bin/bash
#
export MSGDEBUG=1

CMD=$1 ; shift

SERVICE=$(basename $0 .sh)
RUN_SERVICE=$HOME/tpwater/$SERVICE.tcl
LOG_DATE=$(date +%Y%m%d)
LOG_FILE=log/$LOG_DATE-$SERVICE.log
PID_FILE=log/$SERVICE.pid

mkdir -p $HOME/log

case $CMD in
    tail)
        cd $HOME
        tail -f "$LOG_FILE"
    ;;
    stat)
        RUN=$(ps ax | awk '/awk/ { next } /$SERVICE.tcl/ { print $6 }')
        PID=$(cat "$HOME/$PID_FILE" 2> /dev/null)
        if [ "$PID" = "" ] ; then
            STAT="NoPID"
        else
	    kill -0 "$PID" 2> /dev/null
	    if [ $? = "0" ] ; then
		STAT=OK
	    else
		STAT=Huh
	    fi
	fi

        echo "$STAT $PID $RUN"
    ;;
    start)
        cd $HOME
        pid=`cat $PID_FILE 2> /dev/null`
        if [ ! -f $PID_FILE -o "$pid" != "" ] ; then
            if ! kill -0 $pid 2> /dev/null ; then
                echo $(date) START  >> $LOG_FILE
                
                $RUN_SERVICE < /dev/null  >> $LOG_FILE 2>&1 &
                echo $! > $PID_FILE
		exit 0
            else
                echo $SERVICE is already running : $pid 1>&2
		exit 1
            fi
        fi
    ;;
    stop)
        cd $HOME
        kill $(cat $PID_FILE 2> /dev/null) 2> /dev/null
        rm -f $PID_FILE
        echo $(date) STOPED  >> $LOG_FILE
    ;;
    kill)
        pid=$(ps ax | grep  $SERVICE.tcl | grep -v grep | awk '{ print $1 }')
        if [ "$pid" != "" ] ; then
            kill $pid
            echo $(date) KILLED  >> $LOG_FILE
        else
            echo $SERVICE is not running 1>&2
        fi
        ;;
    restart)
        $0 stop
        sleep 5
        $0 start
    ;;

    setup)
    ;;
    crontab)
        cat $HOME/tpwater/crontab | crontab
        crontab -l
    ;;
    up-down)
        sudo ifconfig wlx3c3300700ede down
        sleep 10
        sudo ifconfig wlx3c3300700ede up
    ;;

esac
