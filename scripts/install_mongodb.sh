#!/usr/bin/env bash

# MongoDB installer
# Ref : https://www.linode.com/docs/databases/mongodb/install-mongodb-on-ubuntu-16-04
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 11/12/2021
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

# Make sure only supported distribution can run this installer script.
preflight_system_check

##
# Add MongoDB repository.
#
function add_mongodb_repo() {
    echo "Adding MongoDB ${MONGODB_VERSION} repository..."

    DISTRIB_NAME=${DISTRIB_NAME:-$(get_distrib_name)}
    RELEASE_NAME=${RELEASE_NAME:-$(get_release_name)}
    MONGODB_VERSION=${MONGODB_VERSION:-"5.0"}

    [[ "${RELEASE_NAME}" == "jessie" || "${RELEASE_NAME}" == "xenial" ]] && MONGODB_VERSION="4.4"

    local DISTRIB_ARCH
    case ${ARCH} in
        i386 | i486| i586 | i686)
            DISTRIB_ARCH="i386"
        ;;
        x86_64 | amd64)
            DISTRIB_ARCH="amd64"
        ;;
        arm64 | aarch* | armv8*)
            DISTRIB_ARCH="arm64"
        ;;
        arm | armv7*)
            DISTRIB_ARCH="arm"
        ;;
        *)
            DISTRIB_ARCH="amd64,i386"
        ;;
    esac

    case ${DISTRIB_NAME} in
        debian)
            if [ ! -f "/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list" ]; then
                run touch "/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list"
                run bash -c "echo 'deb [ arch=${DISTRIB_ARCH} ] https://repo.mongodb.org/apt/debian ${RELEASE_NAME}/mongodb-org/${MONGODB_VERSION} main' > /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list"
                run bash -c "wget -qO - 'https://www.mongodb.org/static/pgp/server-${MONGODB_VERSION}.asc' | apt-key add -"
                run apt-get update -qq -y
            else
                info "MongoDB ${MONGODB_VERSION} repository already exists."
            fi
        ;;
        ubuntu)
            if [ ! -f "/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list" ]; then
                run touch "/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list"
                run bash -c "echo 'deb [ arch=${DISTRIB_ARCH} ] https://repo.mongodb.org/apt/ubuntu ${RELEASE_NAME}/mongodb-org/${MONGODB_VERSION} multiverse' > /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list"
                run bash -c "wget -qO - 'https://www.mongodb.org/static/pgp/server-${MONGODB_VERSION}.asc' | apt-key add -"
                run apt-get update -qq -y
            else
                info "MongoDB ${MONGODB_VERSION} repository already exists."
            fi
        ;;
        *)
            error "Unable to add MongoDB repo, unsupported release: ${DISTRIB_NAME^} ${RELEASE_NAME^}."
            echo "Sorry your system is not supported yet, installing from source may fix the issue."
            exit 1
        ;;
    esac
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

        echo "Installing MongoDB server.."

        run apt-get install -qq -y libbson-1.0 libmongoc-1.0-0 \
            mongodb-org mongodb-org-server mongodb-org-shell mongodb-org-tools

        # Enable in start-up
        run systemctl start mongod.service
        run systemctl enable mongod

        if [[ "${DRYRUN}" == true ]]; then
            info "MongoDB server installed in dry run mode."
        else
            echo "MongoDB installation completed."
            echo "After installation finished, you can add a MongoDB administrative user. Example command lines below:";
            cat <<- EOL

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

            # Add MongoDB default admin user.
            if [[ -n $(command -v mongosh) ]]; then
                echo "Adding MongoDB default admin user.."

                MONGODB_ADMIN_USER=${MONGODB_ADMIN_USER:-"lemperdb"}
                MONGODB_ADMIN_PASSWORD=${MONGODB_ADMIN_PASSWORD:-"$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"}

                run mongosh admin --eval "\"db.createUser({'user': '${MONGODB_ADMIN_USER}', 'pwd': '${MONGODB_ADMIN_PASSWORD}', 'roles':[{'role': 'root', 'db': 'admin'}]});\""

                # Save config.
                save_config -e "MONGODB_HOST=127.0.0.1\nMONGODB_PORT=27017\nMONGODB_ADMIN_USER=${MONGODB_ADMIN_USER}\nMONGODB_ADMIN_PASS=${MONGODB_ADMIN_PASSWORD}"

                # Save log.
                save_log -e "MongoDB default admin user is enabled, here is your admin credentials:\nAdmin username: ${MONGODB_ADMIN_USER} | Admin password: ${MONGODB_ADMIN_PASSWORD}\nSave this credentials and use it to authenticate your MongoDB connection."
            fi
        fi
    else
        info "MongoDB server installation skipped."
    fi
}

echo "[MongoDB Server Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v mongod) && "${FORCE_INSTALL}" != true ]]; then
    info "MongoDB server already exists, installation skipped."
else
    init_mongodb_install "$@"
fi
