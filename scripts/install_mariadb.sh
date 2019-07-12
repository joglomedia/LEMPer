#!/usr/bin/env bash

# Include decorator
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    . ${BASEDIR}/helper.sh
fi

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    error "You need to be root to run this script"
    exit 1
fi

function init_mariadb_install() {
    echo ""
    echo "Installing MariaDB (MySQL) database server..."

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
        status -e "\nMariaDB (MySQL) database server installed successfully."
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(which mysql) ]]; then
    warning -e "\nMariaDB/MySQL web server already exists. Installation skipped..."
else
    init_mariadb_install "$@"
fi
