#!/usr/bin/env bash

# MongoDB Uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 12/02/2022
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/utils.sh"

    # Make sure only root can run this installer script.
    requires_root "$@"

    # Make sure only supported distribution can run this installer script.
    preflight_system_check
fi

# Set MongoDB version.
if [[ "${RELEASE_NAME}" == "jessie" || "${RELEASE_NAME}" == "xenial" ]]; then
    MONGODB_VERSION="4.4"
else
    MONGODB_VERSION=${MONGODB_VERSION:-"5.0"}
fi

function remove_mongodb_repo() {
    echo "Removing MongoDB repository..."

    if [[ -f "/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list" ]]; then
        run rm -f "/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list"
        run apt-get update -q -y
    fi

    echo "Removing MongoDB repository key..."

    run bash -c "wget -qO - 'https://www.mongodb.org/static/pgp/server-${MONGODB_VERSION}.asc' | apt-key del -"
}

function init_mongodb_removal() {
    # Stop MongoDB server process.
    if [[ $(pgrep -c mongod) -gt 0 ]]; then
        echo "Stopping mongodb..."
        run systemctl stop mongod
        run systemctl disable mongod
    fi

    if dpkg-query -l | awk '/mongodb/ { print $2 }' | grep -qwE "^mongodb"; then
        echo "Removing MongoDB packages..."

        # Remove MongoDB server.
        #shellcheck disable=SC2046
        run apt-get purge -q -y $(dpkg-query -l | awk '/mongodb/ { print $2 }')

        if [[ "${AUTO_REMOVE}" == true ]]; then
            if [[ "${FORCE_REMOVE}" == true ]]; then
                REMOVE_MONGOD_CONFIG="y"
            else
                REMOVE_MONGOD_CONFIG="n"
            fi
        else
            # Remove MongoDB config files.
            warning "!! This action is not reversible !!"

            while [[ "${REMOVE_MONGOD_CONFIG}" != "y" && "${REMOVE_MONGOD_CONFIG}" != "n" ]]; do
                read -rp "Remove MongoDB database and configuration files? [y/n]: " -e REMOVE_MONGOD_CONFIG
            done
        fi

        if [[ "${REMOVE_MONGOD_CONFIG}" == Y* || "${REMOVE_MONGOD_CONFIG}" == y* ]]; then
            echo "Removing MongoDB data & configs..."

            [ -f /etc/mongod.conf ] && run rm -f /etc/mongod.conf
            [ -d /var/lib/mongodb ] && run rm -fr /var/lib/mongodb

            #echo "All your MongoDB database and configuration files deleted permanently."

            # Remove MongoDB repository.
            remove_mongodb_repo
        fi
    else
        echo "MongoDB package not found, possibly installed from source."

        MONGOD_BIN=$(command -v mongod)

        echo "MongoDB server executable binary: ${MONGOD_BIN}"
        echo "You could remove it manually!"
    fi

    # Final check.
    if [[ "${DRYRUN}" != true ]]; then
        if [[ -z $(command -v mongod) ]]; then
            success "MongoDB server removed succesfully."
        else
            info "Unable to remove MongoDB server."
        fi
    else
        info "MongoDB server removed in dry run mode."
    fi
}

echo "Uninstalling MongoDB ${MONGODB_VERSION} server..."

if [[ -n $(command -v mongod) ]]; then
    if [[ "${AUTO_REMOVE}" == true ]]; then
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
