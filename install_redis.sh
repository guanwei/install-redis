#!/usr/bin/env bash
#====================================================================
# install_redis.sh
#
# Linux Redis Auto Install Script
#
# Copyright (c) 2016, Edward Guan <edward.guan@mkcorp.com>
# All rights reserved.
# Distributed under the GNU General Public License, version 3.0.
#
# Intro: 
#
#====================================================================

# defind functions
msg() {
    printf '%b\n' "$1" >&2
}

title() {
    msg "\e[1;36m${1}\e[0m"
}

success() {
    msg "\e[1;32m[✔]\e[0m ${1}"
}

warning() {
    msg "\e[1;33m${1}${2}\e[0m"
}

error() {
    msg "\e[1;31m[✘]\e[0m ${1}"
    exit 1
}

program_exists() {
    command -v $1 >/dev/null 2>&1
}

function install_redis() {
    # check cluster master name
    if [ -z "$MASTER_NAME" ]; then
        error "Cluster master name can not be empty.\nUsing: -c <MASTER_NAME>"
    fi

    # check cluster master ip
    if [ -z "$MASTER_IP" ]; then
        error "Cluster master ip can not be empty.\nUsing: -m <MASTER_IP>"
    fi

    # check redis auth password
    if [ -z "$REDIS_AUTH" ]; then
        error "Redis auth password can not be empty.\nUsing: -a <REDIS_AUTH>"
    fi

    # check master name
    case $SERVER_TYPE in
        master|slave) ;;
        *) error "Server type must be master/slave.\nUsing: -t <SERVER_TYPE>" ;;
    esac

    echo "MASTER_NAME : $MASTER_NAME"
    echo "SERVER_TYPE : $SERVER_TYPE"
    echo "MASTER_IP   : $MASTER_IP"
    echo "REDIS_PORT  : $REDIS_PORT"
    echo "REDIS_AUTH  : $REDIS_AUTH"
    echo ""

    # install required packages
    title "Installing wget, make, gcc..."
    yum install -y wget make gcc > /dev/null 2>&1
    success "Done."

    # install monit rpm
    title "Installing monit..."
    if [ ! -f "$MONIT_RPM_PATH" ]; then
        warning "WARNING: '$MONIT_RPM_PATH' not exists.\n" \
            "Try to download and install from $MONIT_RPM_URL..."
        wget $MONIT_RPM_URL -P $SCRIPT_PATH || exit 1
    fi
    install_result=$(rpm -U $MONIT_RPM_PATH 2>&1 | awk '{gsub(/^[ \t]+/,"");print}')
    if [ -z "$install_result" ]; then
        success "Installed '$MONIT_RPM_PATH'."
    else
        msg "$install_result"
    fi

    # compile and install redis
    title "Installing redis..."
    if [ ! -d "$REDIS_HOME" ]; then
        REDIS_PKG_PATH="$SCRIPT_PATH/${REDIS_PKG_URL##*/}"
        if [ ! -f "$REDIS_PKG_PATH" ]; then
            warning "WARNING: '$REDIS_PKG_PATH' not exists.\n" \
                "Try to download and install from $REDIS_PKG_URL..."
            wget $REDIS_PKG_URL -P $SCRIPT_PATH || exit 1
        fi
        mkdir -p "$(dirname $REDIS_HOME)"
        tar -xzf $REDIS_PKG_PATH -C "$(dirname $REDIS_HOME)" || exit 1
        cd "$REDIS_HOME"
        make > "$SCRIPT_PATH/redis_build.log" 2>&1 \
            && make install PREFIX=/usr >> "$SCRIPT_PATH/redis_build.log" 2>&1 \
            || error "Failed to install redis.\nSee '$SCRIPT_PATH/redis_build.log' for details."
        success "Installed to '$REDIS_HOME'."
    else
        msg "Redis already installed."
    fi

    # set overcommit_memory to 1
    title "Setting overcommit_memory to 1..."
    sysctl vm.overcommit_memory=1 > /dev/null && sysctl -p > /dev/null || exit 1
    success "Done."

    # install redis service
    title "Installing redis service..."
    mkdir -p "$REDIS_CONFIG_DIR"
    mkdir -p "$REDIS_LOG_DIR"
    mkdir -p "$REDIS_DATA_DIR"
    # update redis config
    sed -e "s|^port .*|port $REDIS_PORT|g" \
        -e "s|^bind .*|bind 0.0.0.0|g" \
        -e "s|^daemonize .*|daemonize yes|g" \
        -e "s|^pidfile .*|pidfile \"$REDIS_PID_FILE\"|g" \
        -e "s|^logfile .*|logfile \"$REDIS_LOG_FILE\"|g" \
        -e "s|^dir .*|dir \"$REDIS_DATA_DIR\"|g" \
        -e "s|^[ #]*masterauth .*|masterauth $REDIS_AUTH|g" \
        -e "s|^[ #]*requirepass .*|requirepass $REDIS_AUTH|g" \
        "$REDIS_HOME/redis.conf" > "$REDIS_CONFIG_FILE" || exit 1
    if [ "$SERVER_TYPE" == "slave" ]; then
        sed -i -r -e "s|^[ #]*slaveof .+|slaveof $MASTER_IP $REDIS_PORT|g" "$REDIS_CONFIG_FILE" || exit 1
    fi
    # update redis init script
    sed -e "s|^REDISPORT=.*|REDISPORT=$REDIS_PORT|g" \
        -e "s|^EXEC=.*|EXEC=$(command -v redis-server)|g" \
        -e "s|^CLIEXEC=.*|CLIEXEC=$(command -v redis-cli)|g" \
        -e "s|^PIDFILE=.*|PIDFILE=\"$REDIS_PID_FILE\"|g" \
        -e "s|^CONF=.*|CONF=\"$REDIS_CONFIG_FILE\"|g" \
        -e "s|^AUTH=.*|AUTH=$REDIS_AUTH|g" \
        "$SCRIPT_PATH/redis_init_script.tpl" > "$REDIS_INIT_SCRIPT" || exit 1
    chmod +x "$REDIS_INIT_SCRIPT"
    success "Installed redis service 'redis_$REDIS_PORT'."

    # install redis sentinel service
    title "Installing redis sentinel service..."
    # update redis sentinel config
    sed -e "s|^port .*|port $SENTINEL_PORT|g" \
        -e "s|^sentinel monitor .*|sentinel monitor $MASTER_NAME $MASTER_IP $REDIS_PORT 2|g" \
        -e "s|^sentinel down-after-milliseconds .*|sentinel down-after-milliseconds $MASTER_NAME 30000|g" \
        -e "s|^sentinel parallel-syncs .*|sentinel parallel-syncs $MASTER_NAME 1|g" \
        -e "s|^sentinel failover-timeout .*|sentinel failover-timeout $MASTER_NAME 180000|g" \
        -e "s|^[ #]*sentinel auth-pass .*|sentinel auth-pass $MASTER_NAME $REDIS_AUTH|g" \
        "$REDIS_HOME/sentinel.conf" > "$SENTINEL_CONFIG_FILE" || exit 1
    if grep -q "^daemonize " "$SENTINEL_CONFIG_FILE" ; then
        sed -i -e "s|^daemonize .*|daemonize yes|g" "$SENTINEL_CONFIG_FILE" || exit 1
    else
        echo "daemonize yes" >> "$SENTINEL_CONFIG_FILE"
    fi
    if grep -q "^pidfile " "$SENTINEL_CONFIG_FILE" ; then
        sed -i -e "s|^pidfile .*|pidfile \"$SENTINEL_PID_FILE\"|g" "$SENTINEL_CONFIG_FILE" || exit 1
    else
        echo "pidfile \"$SENTINEL_PID_FILE\"" >> "$SENTINEL_CONFIG_FILE"
    fi
    if grep -q "^logfile " "$SENTINEL_CONFIG_FILE" ; then
        sed -i -e "s|^logfile .*|logfile \"$SENTINEL_LOG_FILE\"|g" "$SENTINEL_CONFIG_FILE" || exit 1
    else
        echo "logfile \"$SENTINEL_LOG_FILE\"" >> "$SENTINEL_CONFIG_FILE"
    fi
    # update redis sentinel init script
    sed -e "s|^SENTINELPORT=.*|SENTINELPORT=$SENTINEL_PORT|g" \
        -e "s|^EXEC=.*|EXEC=$(command -v redis-server)|g" \
        -e "s|^CLIEXEC=.*|CLIEXEC=$(command -v redis-cli)|g" \
        -e "s|^PIDFILE=.*|PIDFILE=\"$SENTINEL_PID_FILE\"|g" \
        -e "s|^CONF=.*|CONF=\"$SENTINEL_CONFIG_FILE\"|g" \
        -e "s|^AUTH=.*|AUTH=$REDIS_AUTH|g" \
        "$SCRIPT_PATH/sentinel_init_script.tpl" > "$SENTINEL_INIT_SCRIPT" || exit 1
    chmod +x "$SENTINEL_INIT_SCRIPT"
    success "Installed redis sentinel service 'setinel_$SENTINEL_PORT'."

    # monit redis and sentinel
    title "Moniting redis service..."
cat > /etc/monit.d/redis_$REDIS_PORT <<-EOF
check process redis_$REDIS_PORT with pidfile "$REDIS_PID_FILE" 
    start program = "$REDIS_INIT_SCRIPT start"
    stop program = "$REDIS_INIT_SCRIPT stop"
    if failed host 127.0.0.1 port $REDIS_PORT then restart
EOF
    success "Done."

    title "Moniting redis sentinel service..."
cat > /etc/monit.d/sentinel_$SENTINEL_PORT <<-EOF
check process sentinel_$SENTINEL_PORT with pidfile "$SENTINEL_PID_FILE" 
    start program = "$SENTINEL_INIT_SCRIPT start"
    stop program = "$SENTINEL_INIT_SCRIPT stop"
    if failed host 127.0.0.1 port $SENTINEL_PORT then restart
EOF
    success "Done."

    title "Setting monit http interface..."
    sed -i -e "s|\([ ]*set httpd\)|# \1|g" \
        -e "s|\([ ]*use address\)|# \1|g" \
        -e "s|\([ ]*allow\)|# \1|g" /etc/monit.conf || exit 1
cat > /etc/monit.d/http <<-EOF
set httpd port $MONIT_HTTPD_PORT and
    use address 0.0.0.0
    allow 0.0.0.0/0.0.0.0
    allow $MONIT_HTTPD_USER:$MONIT_HTTPD_PWD
EOF
    success "Done."

    title "Setting monit service auto startup and start it..."
    chkconfig monit on
    service monit start || exit 1
    success "Done."

    title "Restarting all monited services..."
    monit restart all || exit 1
    success "All monited services restarted."

    msg "\nThanks for install Redis."
    msg "© `date +%Y`"
}

function remove_redis() {
    # stop redis, sentinel services by monit
    title "Stopping all monited services..."
    monit stop all  || exit 1
    success "Done."

    # remove monit
    title "Removing monit..."
    service monit stop
    rm -f /etc/monit.d/{redis_*,sentinel_*,http}
    rpm -e monit || exit 1
    success "Done."

    # clean redis files
    # Note: log and data will not be delete
    title "Clean redis files..."
    rm -f /etc/init.d/{redis_*,sentinel_*}
    rm -f /usr/bin/redis-*
    rm -rf "$REDIS_CONFIG_DIR"
    rm -rf "$REDIS_HOME"
    success "Done."

    msg "\nThanks for remove Redis."
    msg "© `date +%Y`"
}

function print_usage() {
    echo "Usage: $(basename "$0") [OPTIONS...]"
    echo ""
    echo "Options"
    echo "  [-h|--help]                                 Prints a short help text and exists"
    echo "  [-i|--install]                              Install redis"
    echo "  [-e|--remove]                               Remove (uninstall) redis"
    echo "  [-c|--cluster] <MASTER_NAME>                Set master name of the cluster"
    echo "  [-t|--type] <SERVER_TYPE>                   Set server type (master/slave)"
    echo "  [-m|--master] <MASTER_IP>                   Master server ip of the cluster"
    echo "  [-p|--port] <REDIS_PORT>                    Set redis port"
    echo "  [-a|--auth] <REDIS_AUTH>                    Set redis auth password"
}

warning "Note: This tiny script has been hardcoded specifically for RHEL/CentOS.\n"

if [ $(id -u) != "0" ]; then
    error "You must be root to run this script!"
fi

# read the options
TEMP=`getopt -o hiec:t:m:p:a: --long help,install,remove,cluster:,type:,master:,port:,auth: -n $(basename "$0") -- "$@"`
eval set -- "$TEMP"

# extract options and their arguments into variables.
while true; do
    case "$1" in
        -h|--help) print_usage ; exit 0 ;;
        -i|--install) ACTION=install ; shift ;;
        -e|--remove) ACTION=remove ; shift ;;
        -c|--cluster) MASTER_NAME=$2 ; shift 2 ;;
        -t|--type) SERVER_TYPE=$2 ; shift 2 ;;
        -m|--master) MASTER_IP=$2 ; shift 2 ;;
        -p|--port) REDIS_PORT=$2 ; shift 2 ;;
        -a|--auth) REDIS_AUTH=$2 ; shift 2 ;;
        --) shift ; break ;;
        *) error "Internal error!" ;;
    esac
done

# get script path
SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# load settings
source "$SCRIPT_PATH/settings.conf" || exit 1

# check system type and get monit package path
case $(uname -r) in
    *el7*)
        MONIT_RPM_PATH="$SCRIPT_PATH/${MONIT_EL7_RPM_URL##*/}";
        MONIT_RPM_URL="$MONIT_EL7_RPM_URL" ;;
    *el6*|*amzn1*)
        MONIT_RPM_PATH="$SCRIPT_PATH/${MONIT_EL6_RPM_URL##*/}";
        MONIT_RPM_URL="$MONIT_EL6_RPM_URL" ;;
    *) error "Your system is not RHEL/CentOS" ;;
esac

# if ACTION is install, install rabbitmq server
case $ACTION in
    install)
        install_redis || error "Failed install redis" ;;
    remove)
        remove_redis || error "Failed remove redis" ;;
    *)
        error "Use '-i' to install redis or '-e' to remove redis" ;;
esac