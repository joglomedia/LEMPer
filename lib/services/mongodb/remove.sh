#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Shared Security Helpers                                          |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2026 MasEDI.Net (https://masedi.net/lemper)          |
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

function init_mongodb_removal() {
    # Remove MongoDB default admin.
    echo "Deleting default MongoDB admin account: '${MONGODB_ADMIN_USER}'"
    run mongosh admin --eval "\"db.dropUser('${MONGODB_ADMIN_USER}');\""

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

            # Remove repository.
            run rm -f "/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list"
            run rm -f "/usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg"

            echo "All your MongoDB database and configuration files deleted permanently."
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

function lemper_mongodb_remove_entry() {
    case "${RELEASE_NAME}" in
        bookworm)
            MONGODB_VERSION="7.0"
            ;;
        jammy)
            if version_older_than "${MONGODB_VERSION}" "6.0"; then
                MONGODB_VERSION="6.0"
            fi
            ;;
        *)
            MONGODB_VERSION=${MONGODB_VERSION:-"6.0"}
            ;;
    esac
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
}
