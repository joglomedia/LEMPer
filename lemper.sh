#!/bin/bash

# +-------------------------------------------------------------------------+
# | LEMPer.sh is a simple LEMP stack installer for Debian/Ubuntu            |
# |-------------------------------------------------------------------------+
# | Features    :                                                           |
# |     - Nginx latest                                                      |
# |     - MariaDB 10 (MySQL drop-in replacement)                            |
# |     - PHP latest                                                        |
# |     - Zend OpCache                                                      |
# |     - Memcached latest                                                  |
# |     - ionCube Loader                                                    |
# |     - SourceGuardian Loader                                             |
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

# Work even if somebody does "sh lemper.sh".
set -e

# Try to export global path.
if [ -z "${PATH}" ] ; then
    export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
fi

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
export DISTRIB_NAME && DISTRIB_NAME=$(get_distrib_name)
export DISTRIB_REPO && DISTRIB_REPO=$(get_release_name)

if [[ "${DISTRIB_REPO}" == "unsupported" ]]; then
    error "This Linux distribution isn't supported yet. If you'd like it to be, let us know at https://github.com/joglomedia/LEMPer/issues"
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
    IP_SERVER=$(get_ip_addr)
fi

### Main ###
case "${1}" in
    "--install")
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

        ### Clean-up server ###
        echo ""
        if [ -f scripts/cleanup_server.sh ]; then
            . ./scripts/cleanup_server.sh
        fi

        ### Install dependencies packages ###
        echo ""
        if [ -f scripts/install_dependencies.sh ]; then
            . ./scripts/install_dependencies.sh
        fi

        ### Check and enable swap ###
        echo ""
        enable_swap

        ### Create default account ###
        echo ""
        create_account "${LEMPER_USERNAME}"

        ### Nginx installation ###
        if [ -f scripts/install_nginx.sh ]; then
            echo ""
            . ./scripts/install_nginx.sh
        fi

        ### PHP installation ###
        if [ -f scripts/install_php.sh ]; then
            echo ""
            . ./scripts/install_php.sh
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

        ### Phalcon PHP installation ###
        if [ -f scripts/install_phalcon.sh ]; then
            echo ""
            . ./scripts/install_phalcon.sh
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

        ### Certbot Let's Encrypt SSL installation ###
        if [ -f scripts/install_certbotle.sh ]; then
            echo ""
            . ./scripts/install_certbotle.sh
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

        ### Basic server security ###
        if [ -f scripts/secure_server.sh ]; then
            echo ""
            . ./scripts/secure_server.sh "--install"
        fi

        ### FINAL STEP ###
        if "${FORCE_REMOVE}"; then
            # Cleaning up all build dependencies hanging around on production server?
            echo -e "\nClean up installation process..."
            run apt-get -qq autoremove -y

            # Cleanup build dir
            echo "Clean up build directory..."
            if [ -d "$BUILD_DIR" ]; then
                run rm -fr "$BUILD_DIR"
            fi
        fi

        if "${DRYRUN}"; then
            warning -e "\nLEMPer installation has been completed in dry-run mode."
        else
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
    http://${IP_SERVER}:8082/lcp/dbadmin/

    Database root password: ${MYSQL_ROOT_PASS}

    Mariabackup user information:
    DB Username: ${MARIABACKUP_USER}
    DB Password: ${MARIABACKUP_PASS}

Access to your File manager (TinyFileManager):
    http://${IP_SERVER}:8082/lcp/filemanager/

Please Save & Keep It Private!
~~~~~~~~~~~~~~~~~~~~~~~~~o0o~~~~~~~~~~~~~~~~~~~~~~~~~"

                status "${CREDENTIALS}"

                # Save it to log file
                save_log "${CREDENTIALS}"
            fi
        fi

        echo "
See the log file (lemper.log) for more information.
Now, you can reboot your server and enjoy it!"
    ;;

    "--remove"|"--uninstall")
        header_msg

        echo "Are you sure to remove LEMP stack installation?"
        echo "Please ensure that you've back up your critical data!"

        if ! "${AUTO_REMOVE}"; then
            echo ""
            read -rt 15 -p "Press [Enter] to continue..." </dev/tty
        fi

        # Fix broken install, first?
        echo ""
        run dpkg --configure -a
        run apt-get --fix-broken install

        ### Remove Nginx ###
        if [ -f scripts/remove_nginx.sh ]; then
            echo ""
            . ./scripts/remove_nginx.sh
        fi

        ### Remove PHP & FPM ###
        if [ -f scripts/remove_php.sh ]; then
            echo ""
            . ./scripts/remove_php.sh
        fi

        ### Remove MySQL ###
        if [ -f scripts/remove_mariadb.sh ]; then
            echo ""
            . ./scripts/remove_mariadb.sh
        fi

        ### Remove PHP & FPM ###
        if [ -f scripts/remove_memcached.sh ]; then
            echo ""
            . ./scripts/remove_memcached.sh
        fi

        ### Remove Redis ###
        if [ -f scripts/remove_redis.sh ]; then
            echo ""
            . ./scripts/remove_redis.sh
        fi

        ### Remove MongoDB ###
        if [ -f scripts/remove_mongodb.sh ]; then
            echo ""
            . ./scripts/remove_mongodb.sh
        fi

        ### Remove Certbot LE ###
        if [ -f scripts/remove_certbotle.sh ]; then
            echo ""
            . ./scripts/remove_certbotle.sh
        fi

        ### Remove server security ###
        if [ -f scripts/secure_server.sh ]; then
            echo ""
            . ./scripts/secure_server.sh "--remove"
        fi

        ### Remove 

        # Remove default user account.
        echo ""
        echo "Removing created default account..."
        if "${AUTO_REMOVE}"; then
            REMOVE_ACCOUNT="y"
        else
            while [[ "${REMOVE_ACCOUNT}" != "y" && "${REMOVE_ACCOUNT}" != "n" ]]; do
                read -rp "Remove default LEMPer account? [y/n]: " -i y -e REMOVE_ACCOUNT
            done
        fi
        if [[ "${REMOVE_ACCOUNT}" == Y* || "${REMOVE_ACCOUNT}" == y* || "${FORCE_REMOVE}" == true ]]; then
            if [ "$(type -t delete_account)" == "function" ]; then
                delete_account "lemper"
            fi
        fi

        # Remove created swap.
        echo ""
        echo "Removing created swap..."
        if "${AUTO_REMOVE}"; then
            REMOVE_SWAP="y"
        else
            while [[ "${REMOVE_SWAP}" != "y" && "${REMOVE_SWAP}" != "n" ]]; do
                read -rp "Remove created Swap? [y/n]: " -i y -e REMOVE_SWAP
            done
        fi
        if [[ "${REMOVE_SWAP}" == Y* || "${REMOVE_SWAP}" == y* || "${FORCE_REMOVE}" == true ]]; then
            if [ "$(type -t remove_swap)" == "function" ]; then
                remove_swap
            fi
        fi

        # Remove tools.
        [ -f /usr/local/bin/lemper-cli ] && run rm -f /usr/local/bin/lemper-cli
        [ -d /usr/local/lib/lemper ] && run rm -fr /usr/local/lib/lemper

        # Clean up existing lemper config.
        [ -f /etc/lemper/lemper.conf ] && run rm -f /etc/lemper/lemper.conf

        # Remove unnecessary packages.
        echo -e "\nCleaning up unnecessary packages..."
        run apt-get -qq autoremove -y

        status -e "\nLEMP stack has been removed completely."
        warning -e "\nDid you know? that we're so sad to see you leave :'(
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
