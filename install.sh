#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer is a simple LEMP stack installer for Debian/Ubuntu Linux         |
# |-------------------------------------------------------------------------+
# | Min requirement   : GNU/Linux Debian 8, Ubuntu 18.04 or Linux Mint 17   |
# | Last Update       : 13/02/2022                                          |
# | Author            : MasEDI.Net (me@masedi.net)                          |
# | Version           : 2.x.x                                               |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2022 MasEDI.Net (https://masedi.net/lemper)          |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@lemper.cloud so we can send you a copy immediately.          |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <me@masedi.net>                                |
# +-------------------------------------------------------------------------+

# Work even if somebody does "bash install.sh".
#set -exv -o pipefail # For verbose output.
set -e -o pipefail

# Try to re-export global path.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Get installer base directory.
export BASE_DIR && \
BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    . "${BASE_DIR}/scripts/utils.sh"
fi

# Make sure only root can run this installer script.
requires_root "$@"

# Make sure only supported distribution can run this installer script.
preflight_system_check

##
# Main LEMPer Installer
#
header_msg

echo "Starting LEMPer Stack installation..."
echo "Please ensure that you're on a fresh install!"

if [[ "${AUTO_INSTALL}" != true ]]; then
    echo ""
    read -t 60 -rp "Press [Enter] to continue..." </dev/tty
fi

# Init log.
run init_log

# Init config.
run init_config

### Install dependencies packages ###
if [ -f ./scripts/install_dependencies.sh ]; then
    echo ""
    . ./scripts/install_dependencies.sh
fi

### Server clean-up ###
if [ -f ./scripts/server_cleanup.sh ]; then
    echo ""
    . ./scripts/server_cleanup.sh
fi

### Create default account ###
echo ""
LEMPER_USERNAME=${LEMPER_USERNAME:-"lemper"}
create_account "${LEMPER_USERNAME}"

### Certbot Let's Encrypt SSL installation ###
if [ -f ./scripts/install_certbotle.sh ]; then
    echo ""
    . ./scripts/install_certbotle.sh
fi

### Nginx installation ###
if [ -f ./scripts/install_nginx.sh ]; then
    echo ""
    . ./scripts/install_nginx.sh
fi

### PHP installation ###
if [ -f ./scripts/install_php.sh ]; then
    echo ""
    . ./scripts/install_php.sh
fi

### Phalcon PHP installation ###
if [ -f ./scripts/install_phalcon.sh ]; then
    echo ""
    . ./scripts/install_phalcon.sh
fi

### MySQL database installation ###
if [ -f ./scripts/install_mariadb.sh ]; then
    echo ""
    . ./scripts/install_mariadb.sh
fi

### PostgreSQL database installation ###
if [ -f ./scripts/install_postgres.sh ]; then
    echo ""
    . ./scripts/install_postgres.sh
fi

### Redis database installation ###
if [ -f ./scripts/install_redis.sh ]; then
    echo ""
    . ./scripts/install_redis.sh
fi

### MongoDB database installation ###
if [ -f ./scripts/install_mongodb.sh ]; then
    echo ""
    . ./scripts/install_mongodb.sh
fi

### Memcached installation ###
if [ -f ./scripts/install_memcached.sh ]; then
    echo ""
    . ./scripts/install_memcached.sh
fi

### Imagick installation ###
if [ -f ./scripts/install_imagemagick.sh ]; then
    echo ""
    . ./scripts/install_imagemagick.sh
fi

### Mail server installation ###
if [ -f ./scripts/install_mailer.sh ]; then
    echo ""
    . ./scripts/install_mailer.sh
fi

### FTP installation ###
if [[ "${FTP_SERVER_NAME}" == "pureftpd" || "${FTP_SERVER_NAME}" == "pure-ftpd" ]]; then
    if [ -f ./scripts/install_pureftpd.sh ]; then
        echo ""
        . ./scripts/install_pureftpd.sh
    fi
else
    if [ -f ./scripts/install_vsftpd.sh ]; then
        echo ""
        . ./scripts/install_vsftpd.sh
    fi
fi

### Fail2ban, intrusion prevention software framework. ###
if [ -f ./scripts/install_fail2ban.sh ]; then
    echo ""
    . ./scripts/install_fail2ban.sh
fi

### LEMPer tools installation ###
if [ -f ./scripts/install_tools.sh ]; then
    echo ""
    . ./scripts/install_tools.sh
fi

### Basic server optimization ###
if [ -f ./scripts/server_optimization.sh ]; then
    echo ""
    . ./scripts/server_optimization.sh
fi

### Basic server security setup ###
if [ -f ./scripts/server_security.sh ]; then
    echo ""
    . ./scripts/server_security.sh
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

Default system information:
    Hostname : ${HOSTNAME}
    Server IP: ${SERVER_IP}
    SSH Port : ${SSH_PORT}

LEMPer Stack admin account:
    Username : ${LEMPER_USERNAME}
    Password : ${LEMPER_PASSWORD}

Database administration (Adminer):
    http://${SERVER_IP}:8082/lcp/dbadmin/

    MySQL root password: ${MYSQL_ROOT_PASSWORD}

Mariabackup user information:
    DB Username: ${MARIABACKUP_USER}
    DB Password: ${MARIABACKUP_PASS}"

        if [[ "${INSTALL_POSTGRES}" == true ]]; then
            CREDENTIALS="${CREDENTIALS}

PostgreSQL user information:
    Postgres Superuser: ${POSTGRES_SUPERUSER}

    Postgres DB Username: ${POSTGRES_DB_USER}
    Postgres DB Password: ${POSTGRES_DB_PASS}"
        fi

        if [[ "${INSTALL_MONGODB}" == true ]]; then
            CREDENTIALS="${CREDENTIALS}

MongoDB test admin login:
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

Memcached SASL login:
    Username    : ${MEMCACHED_USERNAME}
    Password    : ${MEMCACHED_PASSWORD}"
        fi

        if [[ "${INSTALL_MAILER}" == true ]]; then
            CREDENTIALS="${CREDENTIALS}

Default Mail service:
    Maildir      : /home/${LEMPER_USERNAME}/Maildir
    Sender Domain: ${SENDER_DOMAIN}
    Sender IP    : ${SERVER_IP}
    IMAP Port    : 143, 993 (SSL/TLS)
    POP3 Port    : 110, 995 (SSL/TLS)

    Domain Key   : lemper._domainkey.${SENDER_DOMAIN}
    DKIM Key     : ${DKIM_KEY}
    SPF Record   : v=spf1 ip4:${SERVER_IP} include:${SENDER_DOMAIN} mx ~all

    Use your default LEMPer stack admin account for Mail login."
        fi

        CREDENTIALS="${CREDENTIALS}

File manager (TinyFileManager):
    http://${SERVER_IP}:8082/lcp/filemanager/

    Use your default LEMPer stack admin account for Filemanager login.

Please Save the above Credentials & Keep it Secure!

~~~~~~~~~~~~~~~~~~~~~~~~~o0o~~~~~~~~~~~~~~~~~~~~~~~~~"

        status "${CREDENTIALS}"

        # Save it to log file
        #save_log "${CREDENTIALS}"

        # Securing LEMPer stack credentials.
        #secure_config
    fi
else
    warning -e "\nLEMPer installation has been completed in dry-run mode."
fi

echo "
See the log file (lemper.log) for more information.
Now, you can reboot your server and enjoy it!
"

info "SECURITY PRECAUTION! Due to the log file contains some credential data,
You SHOULD delete it after your stack completely installed."

footer_msg
