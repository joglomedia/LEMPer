#!/usr/bin/env bash

# Cleanup server
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 01/08/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellchechk source=scripts/helper.sh
    # shellcheck disable=SC1090
    . "${BASEDIR}/helper.sh"
fi

# Define scripts directory.
if echo "${BASEDIR}" | grep -qwE "scripts"; then
    SCRIPTS_DIR="${BASEDIR}"
else
    SCRIPTS_DIR="${BASEDIR}/scripts"
fi

# Make sure only root can run this installer script.
requires_root

echo "Cleaning up server..."
echo ""

# Fix broken install, first?
run dpkg --configure -a
run apt-get --fix-broken install

# Remove Apache2 service if exists.
if [[ -n $(command -v apache2) ]]; then
    warning "It seems Apache web server installed on this server."
    echo "Any other HTTP web server will be removed, otherwise they will conflict."
    read -t 15 -rp "Press [Enter] to continue..." </dev/tty
    echo -e "\nUninstall existing Apache web server..."

    if "${DRYRUN}"; then
        echo "Removing Apache2 installation in dryrun mode."
    else
        run service apache2 stop
        run apt-get --purge remove -y apache2 apache2-doc apache2-utils \
            apache2.2-common apache2.2-bin apache2-mpm-prefork \
            apache2-doc apache2-mpm-worker
    fi
fi

# Remove NGiNX service if exists.
if [[ -n $(command -v nginx) ]]; then
    warning "NGiNX HTTP server already installed on this server. Should we remove it?"
    echo -e "Backup your config and data before continue!\n"

    # shellchechk source=scripts/remove_nginx.sh
    # shellcheck disable=SC1090
    "${SCRIPTS_DIR}/remove_nginx.sh"
fi

# Remove Mysql service if exists.
if [[ -n $(command -v mysql) ]]; then
    warning "MySQL database server already installed on this server. Should we remove it?"
    echo -e "Backup your database before continue!\n"

    # shellchechk source=scripts/remove_mariadb.sh
    # shellcheck disable=SC1090
    "${SCRIPTS_DIR}/remove_mariadb.sh"
fi

# Autoremove packages.
echo -e "\nClean up unused packages."
run apt autoremove -y

if [[ -z $(command -v apache2) && -z $(command -v nginx) && -z $(command -v mysql) ]]; then
    status -e "\nYour server cleaned up."
else
    warning -e "\nYour server cleaned up, but some installation not removed."
fi
