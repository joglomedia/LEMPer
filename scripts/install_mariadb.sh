#!/usr/bin/env bash

# MariaDB (MySQL) Installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04 & 16.04
# Last Build        : 24/08/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellchechk source=scripts/helper.sh
    # shellcheck disable=SC1090
    . "${BASEDIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

function add_mariadb_repo() {
    echo "Adding MariaDB (MySQL) repository..."

    DISTRIB_NAME=${DISTRIB_NAME:-$(get_distrib_name)}
    RELEASE_NAME=${RELEASE_NAME:-$(get_release_name)}
    MYSQL_SERVER=${MYSQL_SERVER:-"mariadb"}
    MYSQL_VERSION=${MYSQL_VERSION:-"10.4"}

    # Add MariaDB source list from MariaDB repo configuration tool.
    if "${DRYRUN}"; then
        status "MariaDB (MySQL) repository added in dryrun mode."
    else
        # Add MariaDB official repo.
        # Ref: https://mariadb.com/kb/en/library/mariadb-package-repository-setup-and-usage/
        run curl -sS -o "${BUILD_DIR}/mariadb_repo_setup" https://downloads.mariadb.com/MariaDB/mariadb_repo_setup && \
        run bash "${BUILD_DIR}/mariadb_repo_setup" --mariadb-server-version="mariadb-${MYSQL_VERSION}" \
            --os-type="${DISTRIB_NAME}" --os-version="${RELEASE_NAME}"
        #run rm -f "${BUILD_DIR}/mariadb_repo_setup"
        run apt-get -qq update -y
    fi
}

function init_mariadb_install() {
    MYSQL_VERSION=${MYSQL_VERSION:-"10.4"}

    if "${AUTO_INSTALL}"; then
        DO_INSTALL_MYSQL="y"
    else
        while [[ "${DO_INSTALL_MYSQL}" != "y" && "${DO_INSTALL_MYSQL}" != "n" ]]; do
            read -rp "Do you want to install MariaDB (MySQL) database server? [y/n]: " \
            -i y -e DO_INSTALL_MYSQL
        done
    fi

    if [[ ${DO_INSTALL_MYSQL} == y* && ${INSTALL_MYSQL} == true ]]; then
        # Add repository.
        add_mariadb_repo

        echo "Installing MariaDB (MySQL drop-in replacement) server..."

        # Install MariaDB
        if hash apt-get 2>/dev/null; then
            run apt-get -qq install -y libmariadb3 libmariadbclient18 "mariadb-client-${MYSQL_VERSION}" \
                "mariadb-client-core-${MYSQL_VERSION}" mariadb-common mariadb-server "mariadb-server-${MYSQL_VERSION}" \
                "mariadb-server-core-${MYSQL_VERSION}" mariadb-backup
        elif hash yum 2>/dev/null; then
            if [ "${VERSION_ID}" == "5" ]; then
                yum -y update
                #yum -y localinstall mariadb-common mariadb-server --nogpgcheck
            else
                yum -y update
            	#yum -y localinstall mariadb-common mariadb-server
            fi
        else
            fail "Unable to install MariaDB, this GNU/Linux distribution is not supported."
        fi

        # Fix MySQL error?
        # Ref: https://serverfault.com/questions/104014/innodb-error-log-file-ib-logfile0-is-of-different-size
        #service mysql stop
        #mv /var/lib/mysql/ib_logfile0 /var/lib/mysql/ib_logfile0.bak
        #mv /var/lib/mysql/ib_logfile1 /var/lib/mysql/ib_logfile1.bak
        #service mysql start

        # Configure MySQL installation.
        if "${DRYRUN}"; then
            warning "MariaDB (MySQL) installed in dryrun mode."
        else
            if [[ -n $(command -v mysql) ]]; then
                if [ ! -f /etc/mysql/my.cnf ]; then
                    run cp -f etc/mysql/my.cnf /etc/mysql/
                fi
                if [ ! -f /etc/mysql/mariadb.cnf ]; then
                    run cp -f etc/mysql/mariadb.cnf /etc/mysql/
                fi
                if [ ! -f /etc/mysql/debian.cnf ]; then
                    run cp -f etc/mysql/debian.cnf /etc/mysql/
                fi
                if [ ! -f /etc/mysql/debian-start ]; then
                    run cp -f etc/mysql/debian-start /etc/mysql/
                    run chmod +x /etc/mysql/debian-start
                fi

                # init script.
                if [ ! -f /etc/init.d/mysql ]; then
                    run cp etc/init.d/mysql /etc/init.d/
                    run chmod ugo+x /etc/init.d/mysql
                fi

                # systemd script.
                if [ ! -f /lib/systemd/system/mariadb.service ]; then
                    run cp etc/systemd/mariadb.service /lib/systemd/system/
                fi
                if [[ ! -f /etc/systemd/system/multi-user.target.wants/mariadb.service && -f /lib/systemd/system/mariadb.service ]]; then
                    run ln -s /lib/systemd/system/mariadb.service \
                        /etc/systemd/system/multi-user.target.wants/mariadb.service
                fi
                if [[ ! -f /etc/systemd/system/mysqld.service && -f /lib/systemd/system/mariadb.service ]]; then
                    run ln -s /lib/systemd/system/mariadb.service \
                        /etc/systemd/system/mysqld.service
                fi
                if [[ ! -f /etc/systemd/system/mysql.service && -f /lib/systemd/system/mariadb.service ]]; then
                    run ln -s /lib/systemd/system/mariadb.service \
                        /etc/systemd/system/mysql.service
                fi

                # Trying to reload daemon.
                run systemctl daemon-reload

                # Enable MariaDB on startup.
                run systemctl enable mariadb.service

                # Unmask systemd service (?)
                #run systemctl unmask mariadb.service

                # Restart MariaDB service daemon.
                #run systemctl start mariadb.service
                run service mysql start

                # MySQL Secure Install.
                if "${AUTO_INSTALL}"; then
                    echo "Securing MariaDB (MySQL) Installation..."

                    # Ref: https://bertvv.github.io/notes-to-self/2015/11/16/automating-mysql_secure_installation/
                    MYSQL_ROOT_PASS=${MYSQL_ROOT_PASS:-$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)}
                    local SQL_QUERY=""

                    # Setting the database root password.
                    SQL_QUERY="ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASS}';"

                    # Delete anonymous users.
                    SQL_QUERY="${SQL_QUERY}
                            DELETE FROM mysql.user WHERE User='';"
                    
                    # Ensure the root user can not log in remotely.
                    SQL_QUERY="${SQL_QUERY}
                            DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"

                    # Remove the test database.
                    SQL_QUERY="${SQL_QUERY}
                            DROP DATABASE IF EXISTS test;
                            DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';"

                    # Flush the privileges tables.
                    SQL_QUERY="${SQL_QUERY}
                            FLUSH PRIVILEGES;"

                    # Root password is blank for newly installed MariaDB (MySQL).
                    if mysql --user=root --password="" -e "${SQL_QUERY}"; then
                        status -n "Success: "
                        echo "Securing MariaDB (MySQL) installation has been done."
                    else
                        error "Unable to secure MariaDB (MySQL) installation."
                    fi
                else
                    # Ref: https://mariadb.com/kb/en/library/security-of-mariadb-root-account/
                    run mysql_secure_installation
                fi
            fi

            if [[ $(pgrep -c mysql) -gt 0 ]]; then
                status "MariaDB (MySQL) installed successfully."

                enable_mariabackup
            else
                warning "Something went wrong with MariaDB (MySQL) installation."
            fi
        fi
    fi
}

function enable_mariabackup() {
    echo ""
    echo "Mariabackup will be installed and enabled by default."
    echo "It is useful to backup and restore MariaDB database."
    echo ""
    sleep 1

    export MARIABACKUP_USER=${MARIABACKUP_USER:-"lemperdb"}
    MARIABACKUP_PASS=${MARIABACKUP_PASS:-$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)}
    export MARIABACKUP_PASS

    echo "Please enter your current MySQL root password to process!"
    until [[ "${MYSQL_ROOT_PASS}" != "" ]]; do
        echo -n "MySQL root password: "; stty -echo; read -r MYSQL_ROOT_PASS; stty echo; echo
    done
    export MYSQL_ROOT_PASS

    # Create default LEMPer database user if not exists.
    if ! mysql -u root -p"${MYSQL_ROOT_PASS}" -e "SELECT User FROM mysql.user;" | grep -q "${MARIABACKUP_USER}"; then
        # Create mariabackup user.
        SQL_QUERY="CREATE USER '${MARIABACKUP_USER}'@'localhost' IDENTIFIED BY '${MARIABACKUP_PASS}';
GRANT RELOAD, PROCESS, LOCK TABLES, REPLICATION CLIENT ON *.* TO '${MARIABACKUP_USER}'@'localhost';"

        mysql -u "root" -p"${MYSQL_ROOT_PASS}" -e "${SQL_QUERY}"

        # Update my.cnf
        MARIABACKUP_CNF="
###################################
# Custom optimization for LEMPer
#
[mariabackup]
user=${MARIABACKUP_USER}
password=${MARIABACKUP_PASS}
open_files_limit=65535
"

        if [ -d /etc/mysql/mariadb.conf.d ]; then
            touch /etc/mysql/mariadb.conf.d/50-mariabackup.cnf
            echo "${MARIABACKUP_CNF}" >> /etc/mysql/mariadb.conf.d/50-mariabackup.cnf
        else
            echo "${MARIABACKUP_CNF}" >> /etc/mysql/my.cnf
        fi

        systemctl restart mariadb.service

        status "Mariaback user '${MARIABACKUP_USER}' added successfully."

        # Save config.
        save_config -e "MYSQL_ROOT_PASS=${MYSQL_ROOT_PASS}\nMARIABACKUP_USERNAME=${MARIABACKUP_USER}\nMARIABACKUP_PASSWORD=${MARIABACKUP_PASS}"

        # Save log.
        save_log -e "MariaDB (MySQL) credentials.\nMySQL Root Password: ${MYSQL_ROOT_PASS}, MariaBackup DB Username: ${MARIABACKUP_USER}, MariaBackup DB Password: ${MARIABACKUP_PASS}\nSave this credential and use it to authenticate your MySQL database connection."
    else
        warning "It seems that user '${MARIABACKUP_USER}' already exists. \
Or try to add mariabackup user manually! "
    fi
}

echo "[MariaDB (MySQL drop-in replacement) Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v mysql) && -n $(command -v mysqld) ]]; then
    warning "MariaDB (MySQL) web server already exists. Installation skipped..."
else
    init_mariadb_install "$@"
fi
