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

    # Add repository
    MONGODB_VERSION=${MONGODB_VERSION:-"4.0"}
    DISTRIB_NAME=${DISTRIB_NAME:-$(get_distrib_name)}
    DISTRIB_REPO=${DISTRIB_REPO:-$(get_release_name)}

    case ${DISTRIB_NAME} in
        debian)
            [[ ${DISTRIB_REPO} == "buster" ]] && local DISTRIB_REPO="stretch"

            if [ ! -f "/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${DISTRIB_REPO}.list" ]; then
                run bash -c "echo 'deb [ arch=amd64 ] https://repo.mongodb.org/apt/debian ${DISTRIB_REPO}/mongodb-org/${MONGODB_VERSION} main' > /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}.list"
                run bash -c "wget -qO - 'https://www.mongodb.org/static/pgp/server-${MONGODB_VERSION}.asc' | apt-key add -"
                #run apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 9DA31620334BD75D9DCB49F368818C72E52529D4
                run apt-get -qq update -y
            else
                warning "MongoDB ${MONGODB_VERSION} repository already exists."
            fi
        ;;
        ubuntu)
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
                    DISTRIB_ARCH="amd64,arm64,i386"
                ;;
            esac

            if [ ! -f "/etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}-${DISTRIB_REPO}.list" ]; then
                run bash -c "echo 'deb [ arch=${DISTRIB_ARCH} ] https://repo.mongodb.org/apt/ubuntu ${DISTRIB_REPO}/mongodb-org/${MONGODB_VERSION} multiverse' > /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}.list"
                run bash -c "wget -qO - 'https://www.mongodb.org/static/pgp/server-${MONGODB_VERSION}.asc' | apt-key add -"
                #run apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 9DA31620334BD75D9DCB49F368818C72E52529D4
                run apt-get -qq update -y
            else
                warning "MongoDB ${MONGODB_VERSION} repository already exists."
            fi
        ;;
        *)
            fail "Unable to install LEMPer: this GNU/Linux distribution is not supported."
        ;;
    esac
}

function init_mongodb_install() {
    if "${AUTO_INSTALL}"; then
        DO_INSTALL_MONGODB="y"
    else
        while [[ "${DO_INSTALL_MONGODB}" != "y" && "${DO_INSTALL_MONGODB}" != "n" ]]; do
            read -rp "Do you want to Install MongoDB? [y/n]: " -i n -e DO_INSTALL_MONGODB
        done
    fi

    if [[ "${DO_INSTALL_MONGODB}" == y* && ${INSTALL_MONGODB} == true ]]; then
        # Add repository.
        add_mongodb_repo

        echo "Installing MongoDB server and MongoDB PHP module..."

        if hash apt-get 2>/dev/null; then
            run apt-get -qq install -y libcurl3 mongodb-org mongodb-org-server mongodb-org-shell mongodb-org-tools
        elif hash yum 2>/dev/null; then
            if [ "${VERSION_ID}" == "5" ]; then
                yum -y update
                #yum -y localinstall mongodb-org mongodb-org-server --nogpgcheck
            else
                yum -y update
            	#yum -y localinstall mongodb-org mongodb-org-server
            fi
        else
            fail "Unable to install LEMPer: this GNU/Linux distribution is not dpkg/yum enabled."
        fi

        # Enable in start-up
        run systemctl restart mongod
        run systemctl enable mongodb
        run systemctl status mongod

        if "${DRYRUN}"; then
            warning "MongoDB server installed in dryrun mode."
        else
            echo "MongoDB installation completed."
            echo "After LEMPer installation finished, create an MongoDB administrative user. Example command lines below:";
            cat <<- _EOF_

mongo
> use admin
> db.createUser({user: "admin", pwd: "<Enter a secure password>", roles:[{role: "root", db: "admin"}]})
> quit()

mongo -u admin -p --authenticationDatabase user-data
> use exampledb
> db.createCollection("exampleCollection", {capped: false})
> var a = { name : "John Doe",  attributes: { age : 30, address : "123 Main St", phone : 8675309 }}
> db.exampleCollection.insert(a)
> WriteResult({ "nInserted" : 1 })
> db.exampleCollection.find()
> db.exampleCollection.find({"name" : "John Doe"})
_EOF_

            sleep 3
        fi
    else
        warning "MongoDB installation skipped..."
    fi
}

echo "[MongoDB Server Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v mongod) ]]; then
    warning "MongoDB server already exists. Installation skipped..."
else
    init_mongodb_install "$@"
fi
