#!/usr/bin/env bash

# MongoDB installer
# Ref : https://www.linode.com/docs/databases/mongodb/install-mongodb-on-ubuntu-16-04
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

# Make sure only root can run this installer script.
requires_root

function add_mongodb_repo() {
    echo "Adding MongoDB ${MONGODB_VERSION} repository..."

    MONGODB_VERSION=${MONGODB_VERSION:-"4.0"}
    DISTRIB_NAME=${DISTRIB_NAME:-$(get_distrib_name)}
    RELEASE_NAME=${RELEASE_NAME:-$(get_release_name)}
    local DISTRIB_ARCH

    case ${ARCH} in
        x86_64)
            DISTRIB_ARCH="amd64"
        ;;
        i386|i486|i586|i686)
            DISTRIB_ARCH="i386"
        ;;
        armv8)
            DISTRIB_ARCH="arm64"
        ;;
        *)
            DISTRIB_ARCH="amd64,i386"
        ;;
    esac

    case ${DISTRIB_NAME} in
        debian)
            case ${RELEASE_NAME} in
                "buster")
                    MONGODB_VERSION="4.2" # Only v4.2 supported for Buster
                ;;
                "jessie")
                    if version_older_than "4.1" "${MONGODB_VERSION}"; then
                        MONGODB_VERSION="4.1"
                    fi
                ;;
            esac

            if [ ! -f "/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list" ]; then
                run touch "/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list"
                run bash -c "echo 'deb [ arch=${DISTRIB_ARCH} ] https://repo.mongodb.org/apt/debian ${RELEASE_NAME}/mongodb-org/${MONGODB_VERSION} main' > /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list"
                run bash -c "wget -qO - 'https://www.mongodb.org/static/pgp/server-${MONGODB_VERSION}.asc' | apt-key add -"
                run apt update -qq -y
            else
                info "MongoDB ${MONGODB_VERSION} repository already exists."
            fi
        ;;
        ubuntu)
            if [ ! -f "/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list" ]; then
                run touch "/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list"
                run bash -c "echo 'deb [ arch=${DISTRIB_ARCH} ] https://repo.mongodb.org/apt/ubuntu ${RELEASE_NAME}/mongodb-org/${MONGODB_VERSION} multiverse' > /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${RELEASE_NAME}.list"
                run bash -c "wget -qO - 'https://www.mongodb.org/static/pgp/server-${MONGODB_VERSION}.asc' | apt-key add -"
                run apt update -qq -y
            else
                info "MongoDB ${MONGODB_VERSION} repository already exists."
            fi
        ;;
        *)
            error "Unable to add MongoDB, unsupported distribution release: ${DISTRIB_NAME^} ${RELEASE_NAME^}."
            echo "Sorry your system is not supported yet, installing from source may fix the issue."
            exit 1
        ;;
    esac
}

function init_mongodb_install() {
    if "${AUTO_INSTALL}"; then
        DO_INSTALL_MONGODB="y"
    else
        while [[ "${DO_INSTALL_MONGODB}" != "y" && "${DO_INSTALL_MONGODB}" != "n" ]]; do
            read -rp "Do you want to install MongoDB? [y/n]: " -i n -e DO_INSTALL_MONGODB
        done
    fi

    if [[ ${DO_INSTALL_MONGODB} == y* && ${INSTALL_MONGODB} == true ]]; then
        # Add repository.
        add_mongodb_repo

        echo "Installing MongoDB server and MongoDB PHP module..."

        if hash apt 2>/dev/null; then
            run apt install -qq -y libbson-1.0 libmongoc-1.0-0 mongodb-org mongodb-org-server \
                mongodb-org-shell mongodb-org-tools
        else
            fail "Unable to install MongoDB, this GNU/Linux distribution is not supported."
        fi

        # Enable in start-up
        run systemctl enable mongod.service
        run systemctl restart mongod

        if "${DRYRUN}"; then
            info "MongoDB server installed in dryrun mode."
        else
            echo "MongoDB installation completed."
            echo "After installation finished, you can add a MongoDB administrative user. Example command lines below:";
            cat <<- _EOF_

mongo
> use admin
> db.createUser({"user": "admin", "pwd": "<Enter a secure password>", "roles":[{"role": "root", "db": "admin"}]})
> quit()

mongo -u admin -p --authenticationDatabase user-data
> use exampledb
> db.createCollection("exampleCollection", {"capped": false})
> var a = {"name": "John Doe", "attributes": {"age": 30, "address": "123 Main St", "phone": 8675309}}
> db.exampleCollection.insert(a)
> WriteResult({ "nInserted" : 1 })
> db.exampleCollection.find()
> db.exampleCollection.find({"name" : "John Doe"})

_EOF_

            # Add MongoDB default admin user.
            if [[ -n $(command -v mongo) ]]; then
                MONGODB_ADMIN_USER=${MONGODB_ADMIN_USER:-"lemperdb"}
                MONGODB_ADMIN_PASS=${MONGODB_ADMIN_PASS:-$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)}
                run mongo admin --eval "db.createUser({'user': '${MONGODB_ADMIN_USER}', 'pwd': '${MONGODB_ADMIN_PASS}', 'roles':[{'role': 'root', 'db': 'admin'}]});" >/dev/null 2>&1

                # Save config.
                save_config -e "MONGODB_HOST=127.0.0.1\nMONGODB_PORT=27017\nMONGODB_ADMIN_USER=${MONGODB_ADMIN_USER}\nMONGODB_ADMIN_PASS=${MONGODB_ADMIN_PASS}"

                # Save log.
                save_log -e "MongoDB default admin user is enabled, here is your admin credentials:\nAdmin username: ${MONGODB_ADMIN_USER} | Admin password: ${MONGODB_ADMIN_PASS}\nSave this credentials and use it to authenticate your MongoDB connection."
            fi
        fi

        # PHP version.
        local PHPv="${1}"
        if [[ -z "${PHPv}" || -n $(grep "\-\-" <<<"${PHPv}") ]]; then
            PHPv=${PHP_VERSION:-"7.3"}
        fi

        # Install PHP MongoDB extension.
        install_php_mongodb "${PHPv}"
    else
        info "MongoDB server installation skipped."
    fi
}

# Install PHP MongoDB extension.
function install_php_mongodb() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.3"}
    fi

    echo -e "\nInstalling PHP ${PHPv} MongoDB extension..."

    local CURRENT_DIR && \
    CURRENT_DIR=$(pwd)
    run cd "${BUILD_DIR}"

    if hash apt 2>/dev/null; then
        run apt install -qq -y "php${PHPv}-mongodb"
    else
        fail "Unable to install PHP ${PHPv} MongoDB, this GNU/Linux distribution is not supported."
    fi

    run git clone --depth=1 -q https://github.com/mongodb/mongo-php-driver.git && \
    run cd mongo-php-driver && \
    run git submodule update --init

    if [[ -n $(command -v "php${PHPv}") ]]; then
        run "/usr/bin/phpize${PHPv}" && \
        run ./configure --with-php-config="/usr/bin/php-config${PHPv}"
    else
        run /usr/bin/phpize && \
        run ./configure
    fi

    run make all && \
    run make install

    PHPLIB_DIR=$("php-config${PHPv}" | grep -wE "\--extension-dir" | cut -d'[' -f2 | cut -d']' -f1)
    if [ -f "${PHPLIB_DIR}/mongodb.so" ]; then
        success "MongoDB module sucessfully installed at ${PHPLIB_DIR}/mongodb.so."
        run chmod 0644 "${PHPLIB_DIR}/mongodb.so"
    fi

    #run service "php${PHPv}-fpm" restart
    run systemctl restart "php${PHPv}-fpm"

    run cd "${CURRENT_DIR}"
}


echo "[MongoDB Server Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v mongod) ]]; then
    info "MongoDB server already exists. Installation skipped..."
else
    init_mongodb_install "$@"
fi
