#!/bin/bash

# +-------------------------------------------------------------------------+
# | LEMPer.sh is a Simple LNMP Installer for Ubuntu                         |
# |-------------------------------------------------------------------------+
# | Features    :                                                           |
# |     - Nginx latest                                                      |
# |     - PHP latest                                                        |
# |     - Zend OpCache                                                      |
# |     - Memcached latest                                                  |
# |     - ionCube Loader                                                    |
# |     - SourceGuardian Loader                                             |
# |     - MariaDB 10 (MySQL drop-in replacement)                            |
# |     - Adminer (PhpMyAdmin replacement)                                  |
# | Min requirement   : GNU/Linux Ubuntu 14.04 or Linux Mint 17             |
# | Last Update       : 10/08/2019                                          |
# | Author            : ESLabs.ID (eslabs.id@gmail.com)                     |
# | Version           : 1.0.0                                               |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2019 ESLabs (https://eslabs.id/lemper)               |
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

set -e # Work even if somebody does "sh lemper.sh".

if [ -z "${PATH}" ] ; then
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
fi

# Unset existing variables.
# shellcheck source=.env
# shellcheck disable=SC2046
unset $(grep -v '^#' .env | grep -v '^\[' | sed -E 's/(.*)=.*/\1/' | xargs)

# Get base directory.
export BASEDIR && \
BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    . scripts/helper.sh
fi

# Make sure only root can run this installer script.
requires_root

# Make sure this script only run on supported distribution.
export DISTRIB_NAME && \
DISTRIB_NAME=$(get_distrib_name)
export DISTRIB_REPO && \
DISTRIB_REPO=$(get_release_name)
if [[ "${DISTRIB_REPO}" == "unsupported" ]]; then
    warning "This installer only work on Ubuntu 16.04 & 18.04 and LinuxMint 18 & 19."
    exit 1
else
    # Get system architecture.
    export ARCH && \
    ARCH=$(uname -p)
    # Get ethernet interface.
    export IFACE && \
    IFACE=$(find /sys/class/net -type l | grep -e "enp\|eth0" | cut -d'/' -f5)
    # Get ethernet IP.
    export IP_SERVER && \
    IP_SERVER=$(ifconfig "${IFACE}" | grep "inet " | cut -d: -f2 | awk '{print $2}')
fi

# Init log.
run init_log

### Main ###
case "${1}" in
    "--install")
        header_msg
        echo "Starting LEMP stack installation..."
        echo "Please ensure that you're on a fresh install!"
        echo ""
        read -t 10 -rp "Press [Enter] to continue..." </dev/tty

        ### Clean-up server ###
        echo ""
        if [ -f scripts/cleanup_server.sh ]; then
            ./scripts/cleanup_server.sh
        fi

        ### Install dependencies packages ###
        echo ""
        if [ -f scripts/install_dependencies.sh ]; then
            ./scripts/install_dependencies.sh
        fi

        ### Check and enable swap ###
        echo ""
        enable_swap

        ### Create default account ###
        echo ""
        create_account "lemper"

        ### Nginx installation ###
        echo ""
        if [ -f scripts/install_nginx.sh ]; then
            ./scripts/install_nginx.sh
        fi

        ### PHP installation ###
        echo ""
        if [ -f scripts/install_php.sh ]; then
            ./scripts/install_php.sh
        fi

        ### Imagick installation ###
        echo ""
        if [ -f scripts/install_imagemagick.sh ]; then
            ./scripts/install_imagemagick.sh
        fi

        ### Memcached installation ###
        echo ""
        if [ -f scripts/install_memcached.sh ]; then
            ./scripts/install_memcached.sh
        fi

        ### MySQL database installation ###
        echo ""
        if [ -f scripts/install_mariadb.sh ]; then
            ./scripts/install_mariadb.sh
        fi

        ### Redis database installation ###
        echo ""
        if [ -f scripts/install_redis.sh ]; then
            ./scripts/install_redis.sh
        fi

        ### MongoDB database installation ###
        echo ""
        if [ -f scripts/install_mongodb.sh ]; then
            ./scripts/install_mongodb.sh
        fi

        ### Certbot Let's Encrypt SSL installation ###
        echo ""
        if [ -f scripts/install_letsencrypt.sh ]; then
            ./scripts/install_letsencrypt.sh
        fi

        ### Mail server installation ###
        echo ""
        if [ -f scripts/install_mailer.sh ]; then
            ./scripts/install_mailer.sh
        fi

        ### Addon-tools installation ###
        echo ""
        if [ -f scripts/install_tools.sh ]; then
            ./scripts/install_tools.sh
        fi

        ### Basic server security ###
        echo ""
        if [ -f scripts/secure_server.sh ]; then
            ./scripts/secure_server.sh
        fi

        ### FINAL STEP ###
        # Cleaning up all build dependencies hanging around on production server?
        run apt-get autoremove -y

        status -e "\nLEMPer installation has been completed."

        ### Recap ###
        if [[ -n "${PASSWORD}" ]]; then
            CREDENTIALS="
Here is your default system account information:
    Hostname : $(hostname)
    Server IP: ${IP_SERVER}
    SSH Port : ${SSH_PORT}
    Username : ${USERNAME}
    Password : ${PASSWORD}

Access to your Database administration (Adminer):
    http://${IP_SERVER}:8082/lcp/dbadminer/

    Database root password: ${MYSQL_ROOT_PASS}

    Mariabackup user information:
    DB Username: ${MARIABACKUP_USER}
    DB Password: ${MARIABACKUP_PASS}

Access to your File manager (FileRun):
    http://${IP_SERVER}:8082/lcp/filemanager/

Please Save & Keep It Private!
~~~~~~~~~~~~~~~~~~~~~~~~~o0o~~~~~~~~~~~~~~~~~~~~~~~~~"

            status "${CREDENTIALS}"

            # Save it to log file
            echo "${CREDENTIALS}" >> lemper.log
        fi

        echo "
See the log file (lemper.log) for more information.
Now, you can reboot your server and enjoy it!"
    ;;

    "--remove"|"--uninstall")
        header_msg
        echo ""
        echo "Are you sure to remove LEMP stack installation?"
        echo "Please ensure that you've back up your critical data!"
        echo ""
        read -rt 10 -p "Press [Enter] to continue..." </dev/tty

        # Fix broken install, first?
        run dpkg --configure -a
        run apt-get --fix-broken install

        ### Remove Nginx ###
        echo ""
        if [ -f scripts/remove_nginx.sh ]; then
            ./scripts/remove_nginx.sh
        fi

        ### Remove PHP & FPM ###
        echo ""
        if [ -f scripts/remove_php.sh ]; then
            ./scripts/remove_php.sh
        fi

        ### Remove PHP & FPM ###
        echo ""
        if [ -f scripts/remove_memcached.sh ]; then
            ./scripts/remove_memcached.sh
        fi

        ### Remove MySQL ###
        echo ""
        if [ -f scripts/remove_mariadb.sh ]; then
            ./scripts/remove_mariadb.sh
        fi

        ### Remove Redis ###
        echo ""
        if [ -f scripts/remove_redis.sh ]; then
            ./scripts/remove_redis.sh
        fi

        # Remove default user account.
        echo ""
        while [[ "${REMOVE_ACCOUNT}" != "y" && "${REMOVE_ACCOUNT}" != "n" && "${AUTO_REMOVE}" != true ]]; do
            read -rp "Remove default LEMPer account? [y/n]: " -i y -e REMOVE_ACCOUNT
        done
        if [[ "${REMOVE_ACCOUNT}" == Y* || "${REMOVE_ACCOUNT}" == y* || "${FORCE_REMOVE}" == true ]]; then
            if [ "$(type -t delete_account)" == "function" ]; then
                delete_account "lemper"
            fi
        fi

        # Remove unnecessary packages.
        echo -e "\nCleaning up unnecessary packages...\n"
        run apt-get autoremove -y

        status -e "\nLEMP stack has been removed completely."
        warning -e "\nDid you know? that e're sad to see you leave :'(
If you are not satisfied with LEMPer stack or have 
any other reasons to uninstall it, please let us know ^^"
    ;;
    --help)
        echo "Please read the README file for more information!"
        exit 0
    ;;
    *)
        fail "Invalid argument: ${1}"
        exit 1
    ;;
esac

footer_msg
