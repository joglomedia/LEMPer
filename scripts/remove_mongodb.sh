#!/usr/bin/env bash

# MongoDB Uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 06/11/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellchechk source=scripts/helper.sh
    # shellcheck disable=SC1090
    . "${BASEDIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

function init_mongodb_removal() {
    # Stop MongoDB server process.
    if [[ $(pgrep -c mongod) -gt 0 ]]; then
        run systemctl stop mongod
    fi

    if dpkg-query -l | awk '/mongodb/ { print $2 }' | grep -qwE "^mongodb"; then
        echo "Found MongoDB package installation. Removing..."

        # Remove MongoDB server.
        #shellcheck disable=SC2046
        run apt remove --purge -qq -y $(dpkg-query -l | awk '/mongodb/ { print $2 }' | grep -wE "^mongodb")
        run rm -f /etc/apt/sources.list.d/mongodb-org-*
        run apt autoremove -qq -y

        # Remove MongoDB config files.
        warning "!! This action is not reversible !!"

        if "${AUTO_REMOVE}"; then
            REMOVE_MONGODCONFIG="y"
        else
            while [[ "${REMOVE_MONGODCONFIG}" != "y" && "${REMOVE_MONGODCONFIG}" != "n" ]]; do
                read -rp "Remove MongoDB database and configuration files? [y/n]: " -e REMOVE_MONGODCONFIG
            done
        fi

        if [[ "${REMOVE_MONGODCONFIG}" == Y* || "${REMOVE_MONGODCONFIG}" == y* || "${FORCE_REMOVE}" == true ]]; then
            [ -f /etc/mongod.conf ] && run rm -fr /etc/mongod.conf
            [ -d /var/lib/mongodb ] && run rm -fr /var/lib/mongodb

            echo "All your MongoDB database and configuration files deleted permanently."
        fi
    else
        echo "MongoDB package not found, possibly installed from source."
        echo "Remove it manually!!"

        MONGOD_BIN=$(command -v mongod)

        echo "MongoDB server binary executable: ${MONGOD_BIN}"
    fi

    # Final test.
    if "${DRYRUN}"; then
        info "MongoDB server removed in dryrun mode."
    else
        if [[ -z $(command -v mongod) ]]; then
            status "MongoDB server removed succesfully."
        else
            info "Unable to remove MongoDB server."
        fi
    fi
}

echo "Uninstalling MongoDB server..."
if [[ -n $(command -v mongod) ]]; then
    if "${AUTO_REMOVE}"; then
        REMOVE_MONGOD="y"
    else
        while [[ "${REMOVE_MONGOD}" != "y" && "${REMOVE_MONGOD}" != "n" ]]; do
            read -rp "Are you sure to remove MongoDB server? [y/n]: " -e REMOVE_MONGOD
        done
    fi

    if [[ "${REMOVE_MONGOD}" == Y* || "${REMOVE_MONGOD}" == y* || "${AUTO_REMOVE}" == true ]]; then
        init_mongodb_removal "$@"
    else
        echo "Found MongoDB server, but not removed."
    fi
else
    info "Oops, MongoDB installation not found."
fi
