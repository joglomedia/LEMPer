#!/bin/bash

# +-------------------------------------------------------------------------+
# | LEMPer.sh is a simple LEMP stack installer for Debian/Ubuntu            |
# |-------------------------------------------------------------------------+
# | Min requirement   : GNU/Linux Debian 8, Ubuntu 16.04 or Linux Mint 17   |
# | Last Update       : 14/01/2020                                          |
# | Author            : MasEDI.Net (me@masedi.net)                     |
# | Version           : 1.0.0                                               |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2021 MasEDI.Net (https://masedi.net/lemper           |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@eslabs.id so we can send you a copy immediately.             |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <eslabs.id@gmail.com>                          |
# +-------------------------------------------------------------------------+

# Work even if somebody does "bash lemper.sh".
set -e

# Try to re-export global path.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Get installer base directory.
export BASEDIR && \
BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    . scripts/helper.sh
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

# Init log.
run init_log

# Init config.
run init_config

### Install dependencies packages ###
echo ""
if [ -f scripts/install_dependencies.sh ]; then
    . ./scripts/install_dependencies.sh
fi

### Clean-up server ###
echo ""
if [ -f scripts/cleanup_server.sh ]; then
    . ./scripts/cleanup_server.sh
fi

### Create and enable swap ###
if "${ENABLE_SWAP}"; then
    echo ""
    enable_swap
fi

### Create default account ###
echo ""
create_account "${LEMPER_USERNAME}"

### Certbot Let's Encrypt SSL installation ###
if [ -f scripts/install_certbotle.sh ]; then
    echo ""
    . ./scripts/install_certbotle.sh
fi

### Nginx installation ###
if [ -f scripts/install_nginx.sh ]; then
    echo ""
    . ./scripts/install_nginx.sh
fi

### PHP installation ###
if [ -f scripts/install_php.sh ]; then
    echo ""
    DEFAULT_PHP_VERSION="7.4"
    . ./scripts/install_php.sh
fi

### Phalcon PHP installation ###
if [ -f scripts/install_phalcon.sh ]; then
    echo ""
    . ./scripts/install_phalcon.sh
fi

### Phalcon PHP installation ###
if [ -f scripts/install_phploader.sh ]; then
    echo ""
    . ./scripts/install_phploader.sh
fi

### Imagick installation ###
if [ -f scripts/install_imagemagick.sh ]; then
    echo ""
    . ./scripts/install_imagemagick.sh
fi

### Memcached installation ###
if [ -f scripts/install_memcached.sh ]; then
    echo ""
    . ./scripts/install_memcached.sh
fi

### MySQL database installation ###
if [ -f scripts/install_mariadb.sh ]; then
    echo ""
    . ./scripts/install_mariadb.sh
fi

### Redis database installation ###
if [ -f scripts/install_redis.sh ]; then
    echo ""
    . ./scripts/install_redis.sh
fi

### MongoDB database installation ###
if [ -f scripts/install_mongodb.sh ]; then
    echo ""
    . ./scripts/install_mongodb.sh
fi

### Mail server installation ###
if [ -f scripts/install_mailer.sh ]; then
    echo ""
    . ./scripts/install_mailer.sh
fi

### Addon-tools installation ###
if [ -f scripts/install_tools.sh ]; then
    echo ""
    . ./scripts/install_tools.sh
fi

### Fail2ban, intrusion prevention software framework. ###
if [ -f scripts/install_fail2ban.sh ]; then
    echo ""
    . ./scripts/install_fail2ban.sh
fi

### Basic server security ###
if [ -f scripts/secure_server.sh ]; then
    echo ""
    . ./scripts/secure_server.sh
fi

### FINAL STEP ###
if "${FORCE_REMOVE}"; then
    # Cleaning up all build dependencies hanging around on production server?
    echo -e "\nClean up installation process..."
    run apt autoremove -qq -y

    # Cleanup build dir
    echo "Clean up build directory..."
    if [ -d "$BUILD_DIR" ]; then
        run rm -fr "$BUILD_DIR"
    fi
fi

if "${DRYRUN}"; then
    warning -e "\nLEMPer installation has been completed in dry-run mode."
else
    status -e "\nCongrats, your LEMP stack installation has been completed."

    ### Recap ###
    if [[ -n "${PASSWORD}" ]]; then
        CREDENTIALS="
Here is your default system information:
    Hostname : ${HOSTNAME}
    Server IP: ${SERVER_IP}
    SSH Port : ${SSH_PORT}

LEMPer stack admin account:
    Username : ${USERNAME}
    Password : ${PASSWORD}

Database administration (Adminer):
    http://${SERVER_IP}:8082/lcp/dbadmin/

    Database root password: ${MYSQL_ROOT_PASS}

    Mariabackup user information:
    DB Username: ${MARIABACKUP_USER}
    DB Password: ${MARIABACKUP_PASS}

File manager (TinyFileManager):
    http://${SERVER_IP}:8082/lcp/filemanager/

    Use your LEMPer stack admin account for login.


Please Save the above Credentials & Keep it Secure!
~~~~~~~~~~~~~~~~~~~~~~~~~o0o~~~~~~~~~~~~~~~~~~~~~~~~~"

        status "${CREDENTIALS}"

        # Save it to log file
        #save_log "${CREDENTIALS}"

        # Securing LEMPer stack credentials.
        #secure_config
    fi
fi

echo "
See the log file (lemper.log) for more information.
Now, you can reboot your server and enjoy it!
"

info "SECURITY PRECAUTION! Due to the log file contains some credential data,
You SHOULD delete it after your stack completely installed."

footer_msg
