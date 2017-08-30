#!/usr/bin/env bash

header_msg
echo "Installing MariaDB server..."

# Install MariaDB
apt-get install -y mariadb-server-10.1 mariadb-client-10.1 mariadb-server-core-10.1 mariadb-common mariadb-server libmariadbclient18 mariadb-client-core-10.1

# Fix MySQL error?
# Ref: https://serverfault.com/questions/104014/innodb-error-log-file-ib-logfile0-is-of-different-size
#service mysql stop
#mv /var/lib/mysql/ib_logfile0 /var/lib/mysql/ib_logfile0.bak
#mv /var/lib/mysql/ib_logfile1 /var/lib/mysql/ib_logfile1.bak
#service mysql start

# MySQL Secure Install
mysql_secure_installation

# Restart MariaDB MySQL server
service mysql restart
