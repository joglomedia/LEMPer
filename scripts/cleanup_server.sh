#!/usr/bin/env bash

# Cleanup server
# Min. Requirement  : GNU/Linux Ubuntu 16.04
# Last Build        : 01/08/2019
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASEDIR}/helper.sh"
fi

# Define scripts directory.
if grep -q "scripts" <<< "${BASEDIR}"; then
    SCRIPTS_DIR="${BASEDIR}"
else
    SCRIPTS_DIR="${BASEDIR}/scripts"
fi

# Make sure only root can run this installer script.
requires_root

echo "Cleaning up server..."

# Fix broken install, first?
if "${FIX_BROKEN}"; then
    echo "Trying to fix broken packages..."
    [ -f /var/lib/dpkg/lock ] && run rm /var/lib/dpkg/lock
    [ -f /var/lib/dpkg/lock-frontend ] && run rm /var/lib/dpkg/lock-frontend
    [ -f /var/cache/apt/archives/lock ] && run rm /var/cache/apt/archives/lock
    run dpkg --configure -a
    run apt-get install -qq -y --fix-broken
fi

# Remove Apache2 service if exists.
if [[ -n $(command -v apache2) || -n $(command -v httpd) ]]; then
    warning -e "\nIt seems that Apache/httpd server installed on this server."
    echo "Any other HTTP web server will be removed, otherwise they will conflict."
    echo ""
    #read -rt 120 -p "Press [Enter] to continue..." </dev/tty

    if "${AUTO_REMOVE}"; then
        REMOVE_APACHE="y"
    else
        while [[ "${REMOVE_APACHE}" != "y" && "${REMOVE_APACHE}" != "n" ]]; do
            read -rp "Are you sure to remove Apache/HTTPD server? [y/n]: " -e REMOVE_APACHE
        done
        echo ""
    fi

    if [[ "${REMOVE_APACHE}" == Y* || "${REMOVE_APACHE}" == y* ]]; then
        echo "Uninstall existing Apache/HTTPD server..."

        if [[ ${DRYRUN} != true ]]; then
            #run service apache2 stop
            run systemctl stop apache2

            # shellcheck disable=SC2046
            run apt-get remove --purge -qq -y $(dpkg-query -l | awk '/apache2/ { print $2 }') \
                $(dpkg-query -l | awk '/httpd/ { print $2 }')
        else
            echo "Removing Apache2 installation in dryrun mode."
        fi
    else
        echo "Found Apache/HTTPD server, but not removed."
    fi
fi

# Remove NGiNX service if exists.
if [[ -n $(command -v nginx) ]]; then
    warning -e "\nNGiNX HTTP server already installed. Should we remove it?"
    echo "Backup your config and data before continue!"

    # shellchechk source=scripts/remove_nginx.sh
    # shellcheck disable=SC1090
    "${SCRIPTS_DIR}/remove_nginx.sh"
fi

# Remove PHP & FPM service if exists.
PHPv=${DEFAULT_PHP_VERSION:-"7.4"}
if [[ -n $(command -v "php${PHPv}") ]]; then
    warning -e "\nPHP & FPM already installed. Should we remove it?"
    echo "Backup your config and data before continue!"

    # shellchechk source=scripts/remove_php.sh
    # shellcheck disable=SC1090
    "${SCRIPTS_DIR}/remove_php.sh" "${PHPv}"
fi

# Remove Mysql service if exists.
if [[ -n $(command -v mysql) ]]; then
    warning -e "\nMariaDB (MySQL) database server already installed. Should we remove it?"
    echo "Backup your database before continue!"

    # shellchechk source=scripts/remove_mariadb.sh
    # shellcheck disable=SC1090
    "${SCRIPTS_DIR}/remove_mariadb.sh"
fi

# Remove default lemper account if exists.
USERNAME=${LEMPER_USERNAME:-"lemper"}
if [[ -n $(getent passwd "${USERNAME}") ]]; then
    warning -e "\nDefault lemper account already exists. Should we remove it?"
    echo "Backup your data before continue!"

    if "${AUTO_REMOVE}"; then
       REMOVE_ACCOUNT="y"
    else
        while [[ "${REMOVE_ACCOUNT}" != "y" && "${REMOVE_ACCOUNT}" != "n" ]]; do
            read -rp "Are you sure to remove default account [y/n]: " -e REMOVE_ACCOUNT
        done
    fi

    if [[ "${REMOVE_ACCOUNT}" == Y* || "${REMOVE_ACCOUNT}" == y* ]]; then
        delete_account "${USERNAME}"

        # Clean up existing lemper config.
        run bash -c "echo '' > /etc/lemper/lemper.conf"
    else
        echo "Found default lemper account, but not removed."
    fi
fi

# Autoremove unused packages.
echo -e "\nCleaning up unused packages..."
run apt-get autoremove -qq -y

if [[ -z $(command -v apache2) && -z $(command -v nginx) && -z $(command -v mysql) ]]; then
    status "Your server cleaned up."
else
    warning "Your server cleaned up, but some installation not removed."
fi
