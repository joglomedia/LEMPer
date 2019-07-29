#!/bin/bash

# +-------------------------------------------------------------------------+
# | LEMPer.sh is a Simple LNMP Installer for Ubuntu                         |
# |-------------------------------------------------------------------------+
# | Features    :                                                           |
# |     - Nginx 1.10                                                        |
# |     - PHP 5.6/7.0/7.1/7.2/7.3                                           |
# |     - Zend OpCache 7.0.3                                                |
# |     - Memcached 1.4.14                                                  |
# |     - ionCube Loader                                                    |
# |     - SourceGuardian Loader                                             |
# |     - MariaDB 10 (MySQL drop-in replacement)                            |
# |     - Adminer (PhpMyAdmin replacement)                                  |
# | Min requirement   : GNU/Linux Ubuntu 14.04 or Linux Mint 17             |
# | Last Update       : 02/07/2019                                          |
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

set -e -o pipefail # Work even if somebody does "sh lemper.sh".

if [ -z "${PATH}" ] ; then
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
fi

# Export environment variables.
if [ -f .env ]; then
    export $(grep -v '^#' .env | grep -v '^\[' | xargs)
    #unset $(grep -v '^#' ../.env | grep -v '^\[' | sed -E 's/(.*)=.*/\1/' | xargs)
else
    echo "Environment variables required, but not found."
    exit 1
fi

# Get base directory.
BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    . scripts/helper.sh
fi

# Make sure only root can run this installer script.
if [ "$(id -u)" -ne 0 ]; then
    error "You need to be root to run this script"
    exit 1
fi

# Init log.
run init_log

# Make sure this script only run on supported distribution.
export DISTRIB_REPO=$(get_release_name)
if [[ "${DISTRIB_REPO}" == "unsupported" ]]; then
    warning "This installer only work on Ubuntu 16.04 & 18.04 and LinuxMint 18 & 19..."
    exit 1
else
    # Set global variables.
    ARCH=$(uname -p)
    IP_SERVER=$(hostname -i)
    # Get ethernet interface.
    IFACE=$(find /sys/class/net -type l | grep enp | cut -d'/' -f5)
fi

### Main ###
case ${1} in
    --install)
        header_msg
        echo ""
        echo "Starting LEMP stack installation..."
        echo "Please ensure that you're on a fresh machine install!"
        echo ""
        read -t 10 -rp "Press [Enter] to continue..." </dev/tty

        ### Clean-up server ###
        if [ -f scripts/cleanup_server.sh ]; then
            . scripts/cleanup_server.sh
        fi

        ### Install pre-requisites packages ###
        if [ -f scripts/install_prerequisites.sh ]; then
            . scripts/install_prerequisites.sh
        fi

        ### Check and enable swap ###
        echo ""
        enable_swap

        ### Create default account ###
        echo ""
        create_account "lemper"

        ### Nginx installation ###
        if [ -f scripts/install_nginx.sh ]; then
            . scripts/install_nginx.sh
        fi

        ### PHP installation ###
        if [ -f scripts/install_php.sh ]; then
            . scripts/install_php.sh
        fi

        ### Memcached installation ###
        if [ -f scripts/install_memcached.sh ]; then
            . scripts/install_memcached.sh
        fi

        ### MySQL database installation ###
        if [ -f scripts/install_mariadb.sh ]; then
            . scripts/install_mariadb.sh
        fi

        ### Redis database installation ###
        if [ -f scripts/install_redis.sh ]; then
            . scripts/install_redis.sh
        fi

        ### Certbot Let's Encrypt SSL installation ###
        if [ -f scripts/install_letsencrypt.sh ]; then
            . scripts/install_letsencrypt.sh
        fi

        ### Mail server installation ###
        if [ -f scripts/install_mailer.sh ]; then
            . scripts/install_mailer.sh
        fi

        ### Addon-tools installation ###
        if [ -f scripts/install_tools.sh ]; then
            . scripts/install_tools.sh
        fi

        ### Basic server security
        if [ -f scripts/secure_server.sh ]; then
            . scripts/secure_server.sh
        fi

        ### FINAL STEP ###
        # Cleaning up all build dependencies hanging around on production server?
        run apt-get autoremove -y >> lemper.log 2>&1

        status -e "\nLEMPer installation has been completed."

        ### Recap ###
        if [[ ! -z "${PASSWORD}" ]]; then
            status "
Here is your default system account information:

    Server IP: ${IP_SERVER}
    SSH Port : ${SSH_PORT}
    Username : ${USERNAME}
    Password : ${PASSWORD}

    Access to your Database administration (Adminer):
    http://${IP_SERVER}:8082/

    Access to your File manager (FileRun):
    http://${IP_SERVER}:8083/

Please Save & Keep It Private!
"

            if [[ ${SSH_PORT} -ne 22 ]]; then
                echo "You're running SSH server with modified config, restart to apply your changes."
                echo "  use this command:  service ssh restart"
            fi
        fi

        echo "
See the log file (lemper.log) for more information.
Now, you can reboot your server and enjoy it!
"
    ;;

    --uninstall)
        header_msg
        echo ""
        echo "Are you sure to remove LEMP stack installation?"
        echo "Please ensure that you've back up your data!"
        echo ""
        read -rt 10 -p "Press [Enter] to continue..." </dev/tty

        # Fix broken install, first?
        run apt-get --fix-broken install >> lemper.log 2>&1

        ### Remove Nginx ###
        if [ -f scripts/remove_nginx.sh ]; then
            . scripts/remove_nginx.sh
        fi

        ### Remove PHP & FPM ###
        if [ -f scripts/remove_php.sh ]; then
            . scripts/remove_php.sh
        fi

        # Remove Memcached if exists
        echo -e "\nUninstalling Memcached..."
        while [[ $REMOVE_MEMCACHED != "y" && $REMOVE_MEMCACHED != "n" ]]; do
            read -pr "Are you sure to remove Memcached? [y/n]: " -e REMOVE_MEMCACHED
        done
        if [[ "$REMOVE_MEMCACHED" == Y* || "$REMOVE_MEMCACHED" == y* ]]; then
            if [[ -n $(command -v memcached) ]]; then
                # Stop Memcached server process
                if [[ $(pgrep -c memcached) -gt 0 ]]; then
                    run service memcached stop
                fi

                run apt-get --purge remove -y libmemcached11 memcached php-igbinary \
                    php-memcache php-memcached php-msgpack >> lemper.log 2>&1
                #run apt-get purge -y libmemcached11 memcached php-igbinary \
                #    php-memcache php-memcached php-msgpack >> lemper.log 2>&1
                #run rm -f /etc/memcached.conf

                if [[ -z $(command -v memcached) ]]; then
                    status "Memcached server removed."
                fi
            else
                warning "Memcached installation not found."
            fi
        else
            echo "Memcache uninstall skipped."
        fi

        # Remove Redis if exists
        echo -e "\nUninstalling Redis..."
        while [[ $REMOVE_REDIS != "y" && $REMOVE_REDIS != "n" ]]; do
            read -pr "Are you sure to remove Redis server? [y/n]: " -e REMOVE_REDIS
        done
        if [[ "$REMOVE_REDIS" == Y* || "$REMOVE_REDIS" == y* ]]; then
            if [[ -n $(command -v redis-server) ]]; then
                # Stop Redis server process
                if [[ $(pgrep -c redis-server) -gt 0 ]]; then
                    run service redis-server stop
                fi

                run apt-get --purge remove -y redis-server php-redis >> lemper.log 2>&1
                #run apt-get purge -y redis-server >> lemper.log 2>&1
                run add-apt-repository -y --remove ppa:chris-lea/redis-server >> lemper.log 2>&1
                #run rm -f /etc/redis/redis.conf

                if [[ -z $(command -v redis-server) ]]; then
                    status "Redis server removed."
                fi
            else
                warning "Redis server installation not found."
            fi
        else
            echo "Redis server uninstall skipped."
        fi

        ### Remove MySQL ###
        if [ -f scripts/remove_mariadb.sh ]; then
            . scripts/remove_mariadb.sh
        fi

        # Remove default user account.
        echo ""
        while [[ $REMOVE_ACCOUNT != "y" && $REMOVE_ACCOUNT != "n" ]]; do
            read -rp "Remove default LEMPer account? [y/n]: " -i y -e REMOVE_ACCOUNT
        done
        if [[ "$REMOVE_ACCOUNT" == Y* || "$REMOVE_ACCOUNT" == y* ]]; then
            if [ "$(type -t delete_account)" == "function" ]; then
                delete_account "lemper"
            fi
        fi

        # Remove unnecessary packages.
        echo -e "\nCleaning up unnecessary packages..."
        run apt-get autoremove -y >> lemper.log 2>&1

        status "LEMP stack has been removed completely."
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
