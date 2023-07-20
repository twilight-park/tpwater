#!/bin/bash
#
# export MSGDEBUG=1

if [ -f $HOME/apikey ] ; then MODE=client
else MODE=hub; fi

SCRIPT_DIR=$(dirname $0)

SERVICE=tpwater-$MODE
SERVICE_EXE=$SERVICE.tcl
RUN_SERVICE=$SCRIPT_DIR/$MODE/$SERVICE_EXE

LOG_DATE=$(date +%Y%m%d)

mkdir -p $SCRIPT_DIR/log
mkdir -p $SCRIPT_DIR/cache
LOG_FILE=$SCRIPT_DIR/log/$LOG_DATE-$SERVICE.log
PID_FILE=$SCRIPT_DIR/log/$SERVICE.pid


CMD=$1 ; shift

case $CMD in
    backup)
        ./$MODE/scripts/pp-back ./$MODE/scripts/data.rkroll.com
        ;;
    tail)
        tail -f "$LOG_FILE"
        ;;
    stat)
        RUN=$(ps ax | awk '/awk/ { next } /'"tclsh .*$SERVICE_EXE"'/ { print $6 }')
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
        pid=$(cat $PID_FILE 2> /dev/null)
        if [ ! -f $PID_FILE -o "$pid" != "" ] ; then
            if ! kill -0 $pid 2> /dev/null ; then
                $0 kill
                echo $(date) START  | tee -a $LOG_FILE 1>&2
                
                $RUN_SERVICE < /dev/null  >> $LOG_FILE 2>&1 &
                echo $! > $PID_FILE
            else
                echo $SERVICE is already running : $pid | tee -a $LOG_FILE 1>&2
            fi
        fi
        ;;
    stop)
        pid=$(cat $PID_FILE 2> /dev/null)
        if [ "$pid" != "" ] ; then
            kill $pid
        fi
        rm  -f $PID_FILE
        echo $(date) STOPED | tee -a  $LOG_FILE 1>&2
        ;;
    kill)
        PID=$(ps ax | awk '/awk/ { next } /'"tclsh .*$SERVICE_EXE"'/ { print $1 }')
        if [ "$PID" != "" ] ; then
            kill $PID
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

    crontab)
        cat $SCRIPT_DIR/share/scripts/crontab | crontab
        crontab -l
        ;;
esac
