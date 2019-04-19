#!/usr/bin/env bash

echo "Adding repositories..."

if [[ "$DISTRIB_RELEASE" == "14.04" || "$MAJOR_RELEASE_NUMBER" == "17" ]]; then
    # Ubuntu release 14.04, LinuxMint 17
    DISTRIB_REPO="trusty"

    # Nginx custom with ngx cache purge
    # https://rtcamp.com/wordpress-nginx/tutorials/single-site/fastcgi-cache-with-purging/
    add-apt-repository ppa:rtcamp/nginx

    # Add MariaDB key servers
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 0xcbcb082a1bb943db
elif [[ "$DISTRIB_RELEASE" == "16.04" || "$MAJOR_RELEASE_NUMBER" == "18" ]]; then
    # Ubuntu release 16.04, LinuxMint 18
    DISTRIB_REPO="xenial"

    # Nginx custom with ngx cache purge
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 3050AC3CD2AE6F03
    sh -c "echo 'deb http://download.opensuse.org/repositories/home:/rtCamp:/EasyEngine/xUbuntu_16.04/ /' >> /etc/apt/sources.list.d/nginx-xenial.list"

    # Add MariaDB key servers
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 0xF1656F24C74CD1D8
elif [[ "$DISTRIB_RELEASE" == "18.04" || "$MAJOR_RELEASE_NUMBER" == "19" ]]; then
    # Ubuntu release 18.04, LinuxMint 19
    DISTRIB_REPO="bionic"

    apt-key fingerprint ABF5BD827BD9BF62
    add-apt-repository ppa:nginx/stable
else
    echo "Sorry, this installation script only work for Ubuntu 14.04, 16.04 & 18.04 and Linux Mint 17, 18 & 19."
    exit 0
fi

# Add MariaDB repo from MariaDB repo configuration tool
if [ ! -f "/etc/apt/sources.list.d/MariaDB-${DISTRIB_REPO}.list" ]; then
touch /etc/apt/sources.list.d/MariaDB-${DISTRIB_REPO}.list
cat > /etc/apt/sources.list.d/MariaDB-${DISTRIB_REPO}.list <<EOL
# MariaDB 10.1 repository list - created 2014-11-30 14:04 UTC
# http://mariadb.org/mariadb/repositories/
deb [arch=amd64] http://ftp.osuosl.org/pub/mariadb/repo/10.1/ubuntu ${DISTRIB_REPO} main
deb-src http://ftp.osuosl.org/pub/mariadb/repo/10.1/ubuntu ${DISTRIB_REPO} main
EOL
fi

# Add PHP (latest stable) from Ondrej's repo
# Source: https://launchpad.net/~ondrej/+archive/ubuntu/php
add-apt-repository ppa:ondrej/php -y
# Fix for NO_PUBKEY key servers error
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 4F4EA0AAE5267A6C

echo "Update repository and install pre-requisites..."

# Update repos
apt-get update -y

# Install pre-requirements
apt-get install -y software-properties-common python-software-properties build-essential git unzip cron curl gnupg2 ca-certificates lsb-release rsync openssl snmp spawn-fcgi fcgiwrap geoip-database

