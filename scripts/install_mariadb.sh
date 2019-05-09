#!/usr/bin/env bash

# Include decorator
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    . ${BASEDIR}/decorator.sh
fi

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    error "This script must be run as root..."
    exit 1
fi

echo -e "\nInstalling MariaDB SQL database server..."

# Install MariaDB
run apt-get install -y mariadb-server libmariadbclient18

# Fix MySQL error?
# Ref: https://serverfault.com/questions/104014/innodb-error-log-file-ib-logfile0-is-of-different-size
#service mysql stop
#mv /var/lib/mysql/ib_logfile0 /var/lib/mysql/ib_logfile0.bak
#mv /var/lib/mysql/ib_logfile1 /var/lib/mysql/ib_logfile1.bak
#service mysql start

# MySQL Secure Install
run mysql_secure_installation

# Restart MariaDB MySQL server
if [[ $(ps -ef | grep -v grep | grep mysql | wc -l) > 0 ]]; then
    run service mysql restart
    status "MariaDB SQL database server installed successfully."
fi
