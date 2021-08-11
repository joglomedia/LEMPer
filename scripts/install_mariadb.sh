#!/usr/bin/env bash

# MariaDB (MySQL) Installer
# Min. Requirement  : GNU/Linux Ubuntu 16.04 & 16.04
# Last Build        : 24/08/2019
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASEDIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

function add_mariadb_repo() {
    echo "Adding MariaDB (MySQL) repository..."

    DISTRIB_NAME=${DISTRIB_NAME:-$(get_distrib_name)}
    RELEASE_NAME=${RELEASE_NAME:-$(get_release_name)}
    MYSQL_SERVER=${MYSQL_SERVER:-"mariadb"}
    MYSQL_VERSION=${MYSQL_VERSION:-"10.6"}

    [ "${RELEASE_NAME}" == "jessie" ] && MYSQL_VERSION="10.5"

    # Add MariaDB official repo.
    # Ref: https://mariadb.com/kb/en/library/mariadb-package-repository-setup-and-usage/

    MARIADB_REPO_SETUP_URL="https://downloads.mariadb.com/MariaDB/mariadb_repo_setup"

    if curl -sLI "${MARIADB_REPO_SETUP_URL}" | grep -q "HTTP/[.12]* [2].."; then
        run curl -sSL -o "${BUILD_DIR}/mariadb_repo_setup" "${MARIADB_REPO_SETUP_URL}" && \
        run bash "${BUILD_DIR}/mariadb_repo_setup" --mariadb-server-version="mariadb-${MYSQL_VERSION}" \
            --os-type="${DISTRIB_NAME}" --os-version="${RELEASE_NAME}" && \
        run apt-get update -qq -y
    else
        error "MariaDB repo installer not found."
    fi
}

function init_mariadb_install() {
    MYSQL_VERSION=${MYSQL_VERSION:-"10.4"}

    if "${AUTO_INSTALL}"; then
        if "${INSTALL_MYSQL}"; then
            DO_INSTALL_MYSQL="y"
        else
            DO_INSTALL_MYSQL="n"
        fi
    else
        while [[ "${DO_INSTALL_MYSQL}" != "y" && "${DO_INSTALL_MYSQL}" != "n" ]]; do
            read -rp "Do you want to install MariaDB (MySQL) database server? [y/n]: " \
            -i y -e DO_INSTALL_MYSQL
        done
    fi

    # Do MariaDB (MySQL) installation here...
    if [[ ${DO_INSTALL_MYSQL} == y* ]]; then
        # Add repository.
        add_mariadb_repo

        echo "Installing MariaDB (MySQL drop-in replacement) server..."

        # Install MariaDB
        if hash apt-get 2>/dev/null; then
            run apt-get install -qq -y libmariadb3 libmariadbclient18 "mariadb-client-${MYSQL_VERSION}" \
                "mariadb-client-core-${MYSQL_VERSION}" mariadb-common mariadb-server "mariadb-server-${MYSQL_VERSION}" \
                "mariadb-server-core-${MYSQL_VERSION}" mariadb-backup
        else
            fail "Unable to install MariaDB, this GNU/Linux distribution is not supported."
        fi

        # Configure MySQL installation.
        if "${DRYRUN}"; then
            info "MariaDB (MySQL) installed in dryrun mode."
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

                # Unmask systemd service (?)
                run systemctl unmask mariadb.service

                # Enable MariaDB on startup.
                run systemctl enable mariadb.service

                # Restart MariaDB service daemon.
                run systemctl start mariadb
                #run service mysql start

                ##
                # MariaDB (MySQL) secure installation
                # Ref: https://mariadb.com/kb/en/library/security-of-mariadb-root-account/
                #
                if "${AUTO_INSTALL}"; then
                    if "${MYSQL_SECURE_INSTALL}"; then
                        echo "Securing MariaDB (MySQL) Installation..."

                        # Ref: https://bertvv.github.io/notes-to-self/2015/11/16/automating-mysql_secure_installation/
                        MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)}
                        local SQL_QUERY=""

                        # Setting the database root password.
                        SQL_QUERY="ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"

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
                            success "Securing MariaDB (MySQL) installation has been done."
                        else
                            error "Unable to secure MariaDB (MySQL) installation."
                        fi
                    fi
                else
                    while [[ "${DO_MYSQL_SECURE_INSTALL}" != "y" && "${DO_MYSQL_SECURE_INSTALL}" != "n" ]]; do
                        read -rp "Do you want to secure MySQL installation? [y/n]: " -e DO_MYSQL_SECURE_INSTALL
                    done

                    if [[ ${DO_MYSQL_SECURE_INSTALL} == y* && ${MYSQL_SECURE_INSTALL} == true ]]; then
                        run mysql_secure_installation
                    fi
                fi
            fi

            if [[ $(pgrep -c mysql) -gt 0 || -n $(command -v mysql) ]]; then
                success "MariaDB (MySQL) installed successfully."

                # Allow remote client access
                allow_remote_client_access

                # Enable Mariabackup
                enable_mariabackup

                # Restart MariaDB (MySQL)
                run systemctl restart mariadb

                if [[ $(pgrep -c mysql) -gt 0 ]]; then
                    success "MariaDB (MySQL) configured successfully."
                elif [[ -n $(command -v mysql) ]]; then
                    # Server died? try to start it.
                    run systemctl start mariadb

                    if [[ $(pgrep -c mysql) -gt 0 ]]; then
                        success "MariaDB (MySQL) configured successfully."
                    else
                        info "Something went wrong with MariaDB (MySQL) installation."
                    fi
                fi
            else
                info "Something went wrong with MariaDB (MySQL) installation."
            fi
        fi
    fi
}

function enable_mariabackup() {
    echo ""
    echo "Mariabackup will be installed and enabled by default."
    echo "It is useful to backup and restore MySQL database."
    echo ""
    sleep 1

    export MARIABACKUP_USER=${MARIABACKUP_USER:-"lemperdb"}
    MARIABACKUP_PASS=${MARIABACKUP_PASS:-$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)}
    export MARIABACKUP_PASS

    #echo "Please enter your current MySQL root password to process!"
    until [[ "${MYSQL_ROOT_PASSWORD}" != "" ]]; do
        echo -n "MySQL root password: "; stty -echo; read -r MYSQL_ROOT_PASSWORD; stty echo; echo
    done
    export MYSQL_ROOT_PASSWORD

    # Create default LEMPer database user if not exists.
    if ! mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT User FROM mysql.user;" | grep -q "${MARIABACKUP_USER}"; then
        # Create mariabackup user.
        SQL_QUERY="CREATE USER '${MARIABACKUP_USER}'@'localhost' IDENTIFIED BY '${MARIABACKUP_PASS}';
                GRANT RELOAD, PROCESS, LOCK TABLES, REPLICATION CLIENT ON *.* TO '${MARIABACKUP_USER}'@'localhost';"

        mysql -u "root" -p"${MYSQL_ROOT_PASSWORD}" -e "${SQL_QUERY}"

        # Update my.cnf
        MARIABACKUP_CNF="###################################
# Custom optimization for LEMPer
# Mariabackup credential
#
[mariabackup]
user=${MARIABACKUP_USER}
password=${MARIABACKUP_PASS}
open_files_limit=65535
"

        if [ -d /etc/mysql/mariadb.conf.d ]; then
            run touch /etc/mysql/mariadb.conf.d/50-mariabackup.cnf
            run bash -c "echo '${MARIABACKUP_CNF}' > /etc/mysql/mariadb.conf.d/50-mariabackup.cnf"
        else
            run bash -c "echo -e '\n${MARIABACKUP_CNF}' >> /etc/mysql/my.cnf"
        fi

        # Restart to take effect.
        #systemctl restart mariadb

        #if [[ $(pgrep -c mysql) -gt 0 ]]; then
        #    success "Mariaback user '${MARIABACKUP_USER}' added successfully."
        #elif [[ -n $(command -v mysql) ]]; then
        #    systemctl start mariadb
        #    if [[ $(pgrep -c mysql) -gt 0 ]]; then
        #        success "Mariaback user '${MARIABACKUP_USER}' added successfully."
        #    else
        #        info "Something went wrong with MariaDB (MySQL) installation."
        #    fi
        #fi

        # Save config.
        save_config -e "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}\nMARIABACKUP_USERNAME=${MARIABACKUP_USER}\nMARIABACKUP_PASSWORD=${MARIABACKUP_PASS}"

        # Save log.
        save_log -e "MariaDB (MySQL) credentials.\nMySQL Root Password: ${MYSQL_ROOT_PASSWORD}, MariaBackup DB Username: ${MARIABACKUP_USER}, MariaBackup DB Password: ${MARIABACKUP_PASS}\nSave this credential and use it to authenticate your MySQL database connection."
    else
        info "It seems that user '${MARIABACKUP_USER}' already exists. You can add mariabackup user manually!"
    fi
}

##
# Allow remote client access
# You need to add the following query to the client account
#CREATE USER 'username'@'ip_address' IDENTIFIED BY 'secret';
#GRANT ALL PRIVILEGES ON *.* TO 'username'@'ip_address' WITH GRANT OPTION;
#CREATE USER 'username'@'%' IDENTIFIED BY 'secret';
#GRANT ALL PRIVILEGES ON *.* TO 'usernemae'@'%' WITH GRANT OPTION;
#FLUSH PRIVILEGES;
#
function allow_remote_client_access() {
    if "${AUTO_INSTALL}"; then
        if "${MYSQL_ALLOW_REMOTE}"; then
            ENABLE_REMOTE_ACCESS="y"
        else
            ENABLE_REMOTE_ACCESS="n"
        fi
    else
        while [[ "${ENABLE_REMOTE_ACCESS}" != "y" && "${ENABLE_REMOTE_ACCESS}" != "n" ]]; do
            read -rp "Do you want to allow MySQL remote client access? [y/n]: " -e ENABLE_REMOTE_ACCESS
        done
    fi

    if [[ ${ENABLE_REMOTE_ACCESS} == y* ]]; then
        REMOTE_CLIENT_CNF="###################################
# Custom optimization for LEMPer
# Allow remote client access
#
[mysqld]
skip-networking=0
skip-bind-address"

        if [ -d /etc/mysql/mariadb.conf.d ]; then
            run touch /etc/mysql/mariadb.conf.d/20-allow-remote-client-access.cnf
            run bash -c "echo '${REMOTE_CLIENT_CNF}' > /etc/mysql/mariadb.conf.d/20-allow-remote-client-access.cnf"
        else
            run bash -c "echo -e '\n${REMOTE_CLIENT_CNF}' >> /etc/mysql/my.cnf"
        fi

        # Restart to take effect.
        #systemctl restart mariadb

        #if [[ $(pgrep -c mysql) -gt 0 ]]; then
        #    success "MySQL remote client access successfully enabled."
        #elif [[ -n $(command -v mysql) ]]; then
        #    systemctl start mariadb
        #    if [[ $(pgrep -c mysql) -gt 0 ]]; then
        #        success "MySQL remote client access successfully enabled."
        #    else
        #        info "Something went wrong with MariaDB (MySQL) installation."
        #    fi
        #fi
    fi
}

echo "[MariaDB (MySQL drop-in replacement) Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v mysql) && -n $(command -v mysqld) ]]; then
    info "MariaDB (MySQL) web server already exists. Installation skipped..."
else
    init_mariadb_install "$@"
fi
