#!/bin/sh
#
# Simple Redis Sentinel init.d script conceived to work on Linux systems
# as it does use of the /proc filesystem.

SENTINELPORT=26379
EXEC=/usr/local/bin/redis-server
CLIEXEC=/usr/local/bin/redis-cli

PIDFILE=/var/run/sentinel_${SENTINELPORT}.pid
CONF="/etc/redis/sentinel_${SENTINELPORT}.conf"
AUTH=""

case "$1" in
    start)
        if [ -f $PIDFILE ]
        then
            echo "$PIDFILE exists, process is already running or crashed"
        else
            echo "Starting Redis Sentinel server..."
            $EXEC $CONF --sentinel
        fi
        ;;
    stop)
        if [ ! -f $PIDFILE ]
        then
            echo "$PIDFILE does not exist, process is not running"
        else
            PID=$(cat $PIDFILE)
            echo "Stopping ..."
            $CLIEXEC -p $SENTINELPORT -a $AUTH shutdown
            while [ -x /proc/${PID} ]
            do
                echo "Waiting for Redis Sentinel to shutdown ..."
                sleep 1
            done
            rm -f $PIDFILE
            echo "Redis Sentinel stopped"
        fi
        ;;
    status)
        PID=$(cat $PIDFILE)
        if [ ! -x /proc/${PID} ]
        then
            echo 'Redis Sentinel is not running'
        else
            echo "Redis Sentinel is running ($PID)"
        fi
        ;;
    restart)
        $0 stop
        $0 start
        ;;
    *)
        echo "Please use start, stop, restart or status as first argument"
        ;;
esac