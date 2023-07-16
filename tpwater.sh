#!/bin/bash
#
# export MSGDEBUG=1

# set -x
# exec > $HOME/tpLOG 2>&1

if [ -f $HOME/apikey ] ; then MODE=client
else MODE=hub; fi

SCRIPT=$(pwd)/$0

SERVICE=tpwater
SERVICE_EXE=tpwater.tcl
RUN_SERVICE=$HOME/tpwater/$MODE/$SERVICE_EXE
LOG_DATE=$(date +%Y%m%d)
LOG_FILE=$HOME/log/$LOG_DATE-$SERVICE.log
PID_FILE=$HOME/log/$SERVICE.pid

mkdir -p $HOME/log

CMD=$1 ; shift

case $CMD in
    backup)
        ./$MODE/scripts/pp-back ./$MODE/scripts/data.rkroll.com
        ;;
    tail)
        cd $HOME
        tail -f "$LOG_FILE"
        ;;
    stat)
        cd $HOME
        RUN=$(ps ax | awk '/awk/ { next } /tpwater_EXE/ { print $6 }')
        PID=$(cat 2> /dev/null $PID_FILE)
        if [ "$PID" = "" ] ; then
            STAT="NoPID"
        else
            kill -0 "$PID"
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
        pid=$(cat $PID_FILE 2> /dev/null)
        if [ ! -f $PID_FILE -o "$pid" != "" ] ; then
            if ! kill -0 $pid 2> /dev/null ; then
                $SCRIPT kill
                echo $(date) START  | tee -a $LOG_FILE 1>&2
                
                $RUN_SERVICE < /dev/null  >> $LOG_FILE 2>&1 &
                echo $! > $PID_FILE
            else
                echo $SERVICE is already running : $pid | tee -a $LOG_FILE 1>&2
            fi
        fi
        ;;
    stop)
        cd $HOME
        kill $(cat $PID_FILE)
        rm  $PID_FILE
        echo $(date) STOPED | tee -a  $LOG_FILE 1>&2
        ;;
    kill)
        cd $HOME
        pid=$(ps ax | grep  $SERVICE_EXE | grep -v grep | awk '{ print $1 }')
        if [ "$pid" != "" ] ; then
            kill $pid
            rm  -f $PID_FILE
            echo $(date) KILLED  | tee -a $LOG_FILE 1>&2
        else
            rm  -f $PID_FILE
            echo $SERVICE is not running | tee -a $LOG_FILE 1>&2
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
        cat $HOME/tpwater/share/crontab | crontab
        crontab -l
        ;;
esac
