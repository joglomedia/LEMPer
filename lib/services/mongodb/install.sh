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

##
# Add MongoDB repository.
##
function add_mongodb_repo() {
    lemper_load_module services/apt/catalog || return 1
    lemper_apt_prepare_repository mongodb || return 1
    lemper_exec apt-get update -q -y
}

##
# Initialize MongoDB Installation.
##
function init_mongodb_install() {
    #local SELECTED_INSTALLER=""

    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_MONGODB}" == true ]]; then
            DO_INSTALL_MONGODB="y"
            #SELECTED_INSTALLER=${MONGODB_INSTALLER:-"repo"}
        else
            DO_INSTALL_MONGODB="n"
        fi
    else
        while [[ "${DO_INSTALL_MONGODB}" != "y" && "${DO_INSTALL_MONGODB}" != "n" ]]; do
            read -rp "Do you want to install MongoDB server? [y/n]: " -i y -e DO_INSTALL_MONGODB
        done
    fi

    if [[ ${DO_INSTALL_MONGODB} == y* || ${DO_INSTALL_MONGODB} == Y* ]]; then
        # Add repository.
        add_mongodb_repo

        echo "Installing MongoDB server..."

        run apt-get install -q -y libbson-1.0 libmongoc-1.0-0 mongodb-org mongodb-org-server \
            mongodb-org-shell mongodb-org-tools mongodb-org-mongos mongodb-database-tools \
            mongodb-org-database-tools-extra mongodb-mongosh

        if [[ "${DRYRUN}" != true ]]; then
            # Enable in start-up.
            echo "Enable MongoDB systemd service..."

            run systemctl start mongod.service
            run systemctl enable mongod

            if [[ $(systemctl is-active mongod) == 'active' ]]; then
                echo "MongoDB server is running."
            else
                echo "MongoDB server is not running."
            fi

            # Add MongoDB default admin user.
            if [[ -n $(command -v mongosh) && $(pgrep -c mongod) -gt 0 ]]; then
                echo "Final test MongoDB service..."

                sleep 3 # Wait for MongoDB to completely started.

                export MONGODB_ADMIN_USER=${MONGODB_ADMIN_USER:-"lemperdb"}
                export MONGODB_ADMIN_PASSWORD=${MONGODB_ADMIN_PASSWORD:-"$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"}

                printf '%s\n' "db.createUser({user: '${MONGODB_ADMIN_USER}', pwd: '${MONGODB_ADMIN_PASSWORD}', roles:[{role: 'root', db: 'admin'}]});" | run mongosh admin --quiet

                # Save config.
                save_config -e "MONGODB_HOST=127.0.0.1\nMONGODB_PORT=27017\nMONGODB_ADMIN_USER=${MONGODB_ADMIN_USER}\nMONGODB_ADMIN_PASS=${MONGODB_ADMIN_PASSWORD}"

                # Save log.
                save_log "MongoDB configured; credentials saved to protected LEMPer configuration."
            else
                echo "MongoDB installation completed with errors on start-up, please check the log file."
                echo -e "After installation finished, you can add a MongoDB administrative user.\nExample command lines below:"
                cat <<-EOL

mongosh
> use admin
> db.createUser({"user": "admin", "pwd": "<Enter a secure password>", "roles":[{"role": "root", "db": "admin"}]})
> quit()

mongosh -u admin -p --authenticationDatabase user-data
> use exampledb
> db.createCollection("exampleCollection", {"capped": false})
> var a = {"name": "John Doe", "attributes": {"age": 30, "address": "123 Main St", "phone": 8675309}}
> db.exampleCollection.insert(a)
> WriteResult({ "nInserted" : 1 })
> db.exampleCollection.find()
> db.exampleCollection.find({"name" : "John Doe"})

EOL
            fi
        else
            info "MongoDB server installed in dry run mode."
        fi
    else
        info "MongoDB server installation skipped."
    fi
}

function lemper_mongodb_install_entry() {
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
    echo "[MongoDB ${MONGODB_VERSION} Server Installation]"
    if [[ -n $(command -v mongod) && "${FORCE_INSTALL}" != true ]]; then
        info "MongoDB server already exists, installation skipped."
    else
        init_mongodb_install "$@"
    fi
}
