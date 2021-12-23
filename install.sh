#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer is a simple LEMP stack installer for Debian/Ubuntu Linux         |
# |-------------------------------------------------------------------------+
# | Min requirement   : GNU/Linux Debian 8, Ubuntu 16.04 or Linux Mint 17   |
# | Last Update       : 18/12/2021                                          |
# | Author            : MasEDI.Net (me@masedi.net)                          |
# | Version           : 2.x.x                                               |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2021 MasEDI.Net (https://masedi.net/lemper)          |
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

# Work even if somebody does "bash lemper.sh".
set -e

# Try to re-export global path.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Get installer base directory.
export BASE_DIR && \
BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    . "${BASE_DIR}/scripts/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

# Make sure only supported distribution can run this installer script.
preflight_system_check


##
# Main LEMPer Installer
#
header_msg

echo "Starting LEMP stack installation..."
echo "Please ensure that you're on a fresh install!"

if ! "${AUTO_INSTALL}"; then
    echo ""
    read -t 60 -rp "Press [Enter] to continue..." </dev/tty
fi

echo ""

# Init log.
run init_log

# Init config.
run init_config

### Install dependencies packages ###
if [ -f ./scripts/install_dependencies.sh ]; then
    echo ""
    . ./scripts/install_dependencies.sh
fi

### Clean-up server ###
if [ -f ./scripts/cleanup_server.sh ]; then
    echo ""
    . ./scripts/cleanup_server.sh
fi

### Create and enable swap ###
if "${ENABLE_SWAP}"; then
    echo ""
    enable_swap
fi

### Create default account ###
USERNAME=${LEMPER_USERNAME:-"lemper"}
create_account "${USERNAME}"

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

### MySQL database installation ###
if [ -f ./scripts/install_mariadb.sh ]; then
    echo ""
    . ./scripts/install_mariadb.sh
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

### Mail server installation ###
if [ -f ./scripts/install_mailer.sh ]; then
    echo ""
    . ./scripts/install_mailer.sh
fi

### VSFTPD installation ###
if [ -f ./scripts/install_vsftpd.sh ]; then
    echo ""
    . ./scripts/install_vsftpd.sh
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

### Basic server security setup ###
if [ -f ./scripts/secure_server.sh ]; then
    echo ""
    . ./scripts/secure_server.sh
fi

### FINAL SETUP ###
if [[ "${FORCE_REMOVE}" == true ]]; then
    # Cleaning up all build dependencies hanging around on production server?
    echo -e "\nClean up installation process..."
    run apt-get autoremove -qq -y

    # Cleanup build dir
    echo "Clean up build directory..."
    if [ -d "$BUILD_DIR" ]; then
        run rm -fr "$BUILD_DIR"
    fi
fi

if [[ "${DRYRUN}" != true ]]; then
    status -e "\nCongrats, your LEMP stack installation has been completed."

    ### Recap ###
    if [[ -n "${PASSWORD}" ]]; then
        CREDENTIALS="
Here is your default system information:
    Hostname : ${HOSTNAME}
    Server IP: ${SERVER_IP}
    SSH Port : ${SSH_PORT}

LEMPer Stack Admin Account:
    Username : ${USERNAME}
    Password : ${PASSWORD}

Database Administration (Adminer):
    http://${SERVER_IP}:8082/lcp/dbadmin/

    Database root password: ${MYSQL_ROOT_PASSWORD}

Mariabackup user information:
    DB Username: ${MARIABACKUP_USER}
    DB Password: ${MARIABACKUP_PASS}

File Manager (TinyFileManager):
    http://${SERVER_IP}:8082/lcp/filemanager/

    Use your default LEMPer stack admin account for Filemanager login.

Default Mail Service:
    Maildir      : /home/${USERNAME}/Maildir
    Sender Domain: ${SENDER_DOMAIN}
    Sender IP    : ${SERVER_IP}
    IMAP Port    : 143, 993 (SSL/TLS)
    POP3 Port    : 110, 995 (SSL/TLS)

    Domain Key   : lemper._domainkey.${SENDER_DOMAIN}
    DKIM Key     : ${DKIM_KEY}
    SPF Record   : v=spf1 ip4:${SERVER_IP} include:${SENDER_DOMAIN} mx ~all

    Use your default LEMPer stack admin account for Mail login.


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
