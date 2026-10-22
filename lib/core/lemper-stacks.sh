#!/usr/bin/env bash

##
# LEMPer Stack Installer & Uninstaller - Shared Logic
# Part of LEMPer Stack - https://github.com/joglomedia/LEMPer
# Author: MasEDI.Net (me@masedi.net)
# Since Version: 2.6.0
#
# This module contains the lemper_install() and lemper_remove() functions
# shared by install.sh, remove.sh, and lemper.sh to avoid code duplication.
# It must be sourced, not executed directly.
##

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script should be sourced, not executed directly."
    exit 1
fi

# Resolve BASE_DIR so this module can find scripts/ regardless of CWD.
# Entry points (install.sh, remove.sh) already set BASE_DIR; this is a fallback
# for lemper.sh which uses relative sourcing.
if [[ -z "${BASE_DIR:-}" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[1]:-$0}" )/.." >/dev/null 2>&1 && pwd )
    export BASE_DIR
fi

##
# Main LEMPer Installer
##
function lemper_install() {
    echo "Starting LEMPer Stack installation..."
    echo "Please ensure that you're on a fresh install!"
    echo -e "\nPress [Ctrl+C] to abort the installation process."

    sleep 3

    if [[ "${AUTO_INSTALL}" != true ]]; then
        echo ""
        read -t 60 -rp "Press [Enter] to continue..." </dev/tty
    fi

    # Init log.
    run init_log

    # Init config.
    run init_config

    ### Install dependencies packages ###
    if [ -f "${BASE_DIR}/scripts/install_dependencies.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/install_dependencies.sh"
    fi

    ### Server clean-up ###
    if [ -f "${BASE_DIR}/scripts/server_cleanup.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/server_cleanup.sh"
    fi

    ### Create default account ###
    echo ""
    LEMPER_USERNAME=${LEMPER_USERNAME:-"lemper"}
    create_account "${LEMPER_USERNAME}"

    ### Certbot Let's Encrypt SSL installation ###
    if [ -f "${BASE_DIR}/scripts/install_certbotle.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/install_certbotle.sh"
    fi

    ### Nginx installation ###
    if [ -f "${BASE_DIR}/scripts/install_nginx.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/install_nginx.sh"
    fi

    ### PHP installation ###
    if [ -f "${BASE_DIR}/scripts/install_php.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/install_php.sh"
    fi

    ### Phalcon PHP installation ###
    if [ -f "${BASE_DIR}/scripts/install_phalcon.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/install_phalcon.sh"
    fi

    ### MySQL database installation ###
    if [ -f "${BASE_DIR}/scripts/install_mariadb.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/install_mariadb.sh"
    fi

    ### PostgreSQL database installation ###
    if [ -f "${BASE_DIR}/scripts/install_postgres.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/install_postgres.sh"
    fi

    ### Redis database installation ###
    if [ -f "${BASE_DIR}/scripts/install_redis.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/install_redis.sh"
    fi

    ### MongoDB database installation ###
    if [ -f "${BASE_DIR}/scripts/install_mongodb.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/install_mongodb.sh"
    fi

    ### Memcached installation ###
    if [ -f "${BASE_DIR}/scripts/install_memcached.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/install_memcached.sh"
    fi

    ### Imagick installation ###
    if [ -f "${BASE_DIR}/scripts/install_imagemagick.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/install_imagemagick.sh"
    fi

    ### Mail server installation ###
    if [ -f "${BASE_DIR}/scripts/install_mailer.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/install_mailer.sh"
    fi

    ### FTP installation ###
    if [[ "${FTP_SERVER_NAME}" == "pureftpd" || "${FTP_SERVER_NAME}" == "pure-ftpd" ]]; then
        if [ -f "${BASE_DIR}/scripts/install_pureftpd.sh" ]; then
            echo ""
            . "${BASE_DIR}/scripts/install_pureftpd.sh"
        fi
    else
        if [ -f "${BASE_DIR}/scripts/install_vsftpd.sh" ]; then
            echo ""
            . "${BASE_DIR}/scripts/install_vsftpd.sh"
        fi
    fi

    ### Fail2ban, intrusion prevention software framework. ###
    if [ -f "${BASE_DIR}/scripts/install_fail2ban.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/install_fail2ban.sh"
    fi

    ### LEMPer tools installation ###
    if [ -f "${BASE_DIR}/scripts/install_tools.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/install_tools.sh"
    fi

    ### Bun.js runtime installation ###
    if [ -f "${BASE_DIR}/scripts/install_bun.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/install_bun.sh"
    fi

    ### Basic server optimization ###
    if [ -f "${BASE_DIR}/scripts/server_optimization.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/server_optimization.sh"
    fi

    ### Basic server security setup ###
    if [ -f "${BASE_DIR}/scripts/server_security.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/server_security.sh"
    fi

    ### FINAL SETUP ###
    if [[ "${FORCE_REMOVE}" == true ]]; then
        # Cleaning up all build dependencies hanging around on production server?
        echo -e "\nClean up installation process..."
        run apt-get autoremove -q -y

        # Cleanup build dir
        echo "Clean up build directory..."
        if [ -d "${BUILD_DIR}" ]; then
            run rm -fr "${BUILD_DIR}"
        fi
    fi

    if [[ "${DRYRUN}" != true ]]; then
        status -e "\nCongrats, your LEMPer Stack installation has been completed."

        ### Recap ###
        if [[ -n "${LEMPER_PASSWORD}" ]]; then
            CREDENTIALS="
~~~~~~~~~~~~~~~~~~~~~~~~~o0o~~~~~~~~~~~~~~~~~~~~~~~~~

Default System Information:
    Hostname : ${HOSTNAME}
    Server IP: ${SERVER_IP}
    SSH Port : ${SSH_PORT}

LEMPer Stack Admin Account:
    Username : ${LEMPER_USERNAME}
    Password : ${LEMPER_PASSWORD}

Database Administration (Adminer):
    http://${SERVER_IP}:8082/lcp/dbadmin/

    MySQL root password: ${MYSQL_ROOT_PASSWORD}

Mariabackup user information:
    DB Username: ${MARIABACKUP_USER}
    DB Password: ${MARIABACKUP_PASS}"

            if [[ "${INSTALL_POSTGRES}" == true ]]; then
                CREDENTIALS="${CREDENTIALS}

PostgreSQL user information:
    Default Postgres User: ${POSTGRES_SUPERUSER}

    PostgresSQL DB Username: ${POSTGRES_DB_USER}
    PostgresSQL DB Password: ${POSTGRES_DB_PASS}"
            fi

            if [[ "${INSTALL_MONGODB}" == true ]]; then
                CREDENTIALS="${CREDENTIALS}

MongoDB Test Admin Login:
    Username    : ${MONGODB_ADMIN_USER}
    Password    : ${MONGODB_ADMIN_PASSWORD}"
            fi

            if [[ "${INSTALL_REDIS}" == true && "${REDIS_REQUIRE_PASSWORD}" == true ]]; then
                CREDENTIALS="${CREDENTIALS}

Redis required password enabled:
    Password    : ${REDIS_PASSWORD}"
            fi

            if [[ "${INSTALL_MEMCACHED}" == true && "${MEMCACHED_SASL}" == true ]]; then
                CREDENTIALS="${CREDENTIALS}

Memcached SASL Login:
    Username    : ${MEMCACHED_USERNAME}
    Password    : ${MEMCACHED_PASSWORD}"
            fi

            if [[ "${INSTALL_MAILER}" == true ]]; then
                CREDENTIALS="${CREDENTIALS}

Default Mail Service:
    Maildir      : /home/${LEMPER_USERNAME}/Maildir
    Sender Domain: ${SENDER_DOMAIN}
    Sender IP    : ${SERVER_IP}
    IMAP Port    : 143, 993 (SSL/TLS)
    POP3 Port    : 110, 995 (SSL/TLS)

    Domain Key   : ${DOMAIN_KEY}
    DKIM Key     : ${DKIM_KEY}
    SPF Record   : ${SPF_RECORD}

    Use your default LEMPer Stack admin account for Mail login."
            fi

            CREDENTIALS="${CREDENTIALS}

File manager (TinyFileManager):
    http://${SERVER_IP}:8082/lcp/filemanager/

    Use your default LEMPer Stack admin account for Filemanager login.

Please Save the above Credentials & Keep it Secure!

~~~~~~~~~~~~~~~~~~~~~~~~~o0o~~~~~~~~~~~~~~~~~~~~~~~~~"

            # Credentials are saved securely to /etc/lemper/lemper.conf (mode 0600, root-only).
            # They are NOT printed to stdout, emailed, or written to the log file
            # to prevent exposure in terminal history, CI logs, or email inboxes.
            info "Installation credentials have been saved to /etc/lemper/lemper.conf (root-only, mode 0600)."
            info "To view them, run: sudo cat /etc/lemper/lemper.conf"
        fi
    else
        warning -e "\nLEMPer installation has been completed in dry-run mode."
    fi

    echo -e "\nSee the log file (lemper.log) for more information.
Now, you can reboot your server and enjoy it!\n"

    info "SECURITY: Credentials are stored in /etc/lemper/lemper.conf (mode 0600, root-only).
Keep this file secure and delete the installation log after setup."
}

##
# Main LEMPer Uninstaller
##
function lemper_remove() {
    echo "Are you sure to remove LEMPer Stack installation?"
    echo "Please ensure that you've backed up your critical data!"
    echo ""

    if [[ "${AUTO_REMOVE}" == false ]]; then
        read -rt 20 -p "Press [Enter] to continue..." </dev/tty
    fi

    # Fix broken install, first?
    if [[ "${FIX_BROKEN_INSTALL}" == true ]]; then
        run dpkg --configure -a
        run apt-get install -q -y --fix-broken
    fi

    ### Remove Nginx ###
    if [ -f "${BASE_DIR}/scripts/remove_nginx.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/remove_nginx.sh"
    fi

    ### Remove MySQL ###
    if [ -f "${BASE_DIR}/scripts/remove_mariadb.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/remove_mariadb.sh"
    fi

    ### Remove PostgreSQL ###
    if [ -f "${BASE_DIR}/scripts/remove_postgres.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/remove_postgres.sh"
    fi

    ### Remove PHP & FPM ###
    if [ -f "${BASE_DIR}/scripts/remove_php.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/remove_php.sh"
    fi

    ### Remove Redis ###
    if [ -f "${BASE_DIR}/scripts/remove_redis.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/remove_redis.sh"
    fi

    ### Remove MongoDB ###
    if [ -f "${BASE_DIR}/scripts/remove_mongodb.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/remove_mongodb.sh"
    fi

    ### Remove PHP & FPM ###
    if [ -f "${BASE_DIR}/scripts/remove_memcached.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/remove_memcached.sh"
    fi

    ### Mail server installation ###
    if [ -f "${BASE_DIR}/scripts/remove_mailer.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/remove_mailer.sh"
    fi

    ### Remove FTP installation ###
    if [[ "${FTP_SERVER_NAME}" == "pureftpd" || "${FTP_SERVER_NAME}" == "pure-ftpd" ]]; then
        if [ -f "${BASE_DIR}/scripts/remove_pureftpd.sh" ]; then
            echo ""
            . "${BASE_DIR}/scripts/remove_pureftpd.sh"
        fi
    else
        if [ -f "${BASE_DIR}/scripts/remove_vsftpd.sh" ]; then
            echo ""
            . "${BASE_DIR}/scripts/remove_vsftpd.sh"
        fi
    fi

    ### Remove Fail2ban ###
    if [ -f "${BASE_DIR}/scripts/remove_fail2ban.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/remove_fail2ban.sh"
    fi

    ### Remove Certbot ###
    if [ -f "${BASE_DIR}/scripts/remove_certbotle.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/remove_certbotle.sh"
    fi

    ### Remove Bun.js runtime ###
    if [ -f "${BASE_DIR}/scripts/remove_bun.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/remove_bun.sh"
    fi

    ### Remove server security setup ###
    if [ -f "${BASE_DIR}/scripts/server_security.sh" ]; then
        echo ""
        . "${BASE_DIR}/scripts/server_security.sh" --remove
    fi

    ### Remove default user account ###
    echo ""
    echo "Removing created default account..."

    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_ACCOUNT="y"
    else
        while [[ "${REMOVE_ACCOUNT}" != "y" && "${REMOVE_ACCOUNT}" != "n" ]]; do
            read -rp "Remove default LEMPer account? [y/n]: " -i y -e REMOVE_ACCOUNT
        done
    fi

    if [[ "${REMOVE_ACCOUNT}" == Y* || "${REMOVE_ACCOUNT}" == y* || "${FORCE_REMOVE}" == true ]]; then
        if [[ "$(type -t delete_account)" == "function" ]]; then
            delete_account "${LEMPER_USERNAME}"
        fi
    fi

    ### Remove created swap ###
    echo ""
    echo "Removing created swap..."

    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_SWAP="y"
    else
        while [[ "${REMOVE_SWAP}" != "y" && "${REMOVE_SWAP}" != "n" ]]; do
            read -rp "Remove created Swap? [y/n]: " -e REMOVE_SWAP
        done
    fi

    if [[ "${REMOVE_SWAP}" == Y* || "${REMOVE_SWAP}" == y* || "${FORCE_REMOVE}" == true ]]; then
        if [[ "$(type -t remove_swap)" == "function" ]]; then
            remove_swap
        fi
    fi

    ### Remove web tools ###
    [ -f /usr/local/bin/lemper-cli ] && run rm -f /usr/local/bin/lemper-cli
    [ -d /usr/local/lib/lemper ] && run rm -fr /usr/local/lib/lemper

    # Clean up existing lemper config.
    [ -f /etc/lemper/lemper.conf ] && run rm -f /etc/lemper/lemper.conf
    [ -d /etc/lemper/cli-plugins ] && run rm -fr /etc/lemper/cli-plugins

    ### Remove unnecessary packages ###
    echo -e "\nCleaning up unnecessary packages..."

    run apt-get autoremove -q -y && \
    run apt-get autoclean -q -y && \
    run apt-get clean -q -y

    echo -e "\nLEMPer Stack has been removed completely."
    warning -e "\nDid you know? that we're so sad to see you leave :'(
If you are not satisfied with LEMPer Stack or have 
any other reasons to uninstall it, please let us know ^^

Submit your issue here: https://github.com/joglomedia/LEMPer/issues"
}
