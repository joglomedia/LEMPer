#!/usr/bin/env bash

# Include decorator
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    . ${BASEDIR}/decorator.sh
fi

echo "Adding repositories..."

if [[ "$DISTRIB_RELEASE" == "14.04" || "$DISTRIB_RELEASE" == "LM17" ]]; then
    # Ubuntu release 14.04, LinuxMint 17
    DISTRIB_REPO="trusty"
    ARCH_REPO="amd64,i386,ppc64el"

    # Nginx custom with ngx cache purge
    # https://rtcamp.com/wordpress-nginx/tutorials/single-site/fastcgi-cache-with-purging/
    run add-apt-repository -y ppa:rtcamp/nginx
    NGX_PACKAGE="nginx-custom"

    # MariaDB 10.2 repo
    MARIADB_VER="10.2"
    run apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 0xcbcb082a1bb943db
    #add-apt-repository 'deb http://ftp.osuosl.org/pub/mariadb/repo/10.2/ubuntu trusty main'
elif [[ "$DISTRIB_RELEASE" == "16.04" || "$DISTRIB_RELEASE" == "LM18" ]]; then
    # Ubuntu release 16.04, LinuxMint 18
    DISTRIB_REPO="xenial"
    ARCH_REPO="amd64,arm64,i386,ppc64el"

    # Nginx custom repo with ngx cache purge
    run apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3050AC3CD2AE6F03
    run sh -c "echo 'deb http://download.opensuse.org/repositories/home:/rtCamp:/EasyEngine/xUbuntu_16.04/ /' >> /etc/apt/sources.list.d/nginx-xenial.list"
    NGX_PACKAGE="nginx-custom"

    # MariaDB 10.3 repo
    MARIADB_VER="10.3"
    run apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 0xF1656F24C74CD1D8
    #add-apt-repository 'deb [arch=amd64,i386,ppc64el] http://ftp.osuosl.org/pub/mariadb/repo/10.3/ubuntu xenial main'
elif [[ "$DISTRIB_RELEASE" == "18.04" || "$DISTRIB_RELEASE" == "LM19" ]]; then
    # Ubuntu release 18.04, LinuxMint 19
    DISTRIB_REPO="bionic"
    ARCH_REPO="amd64,arm64,ppc64el"

    # Nginx repo
    run apt-key fingerprint ABF5BD827BD9BF62
    run add-apt-repository -y ppa:nginx/stable
    NGX_PACKAGE="nginx-stable"

    # MariaDB 10.3 repo
    MARIADB_VER="10.3"
    run apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 0xF1656F24C74CD1D8
    #add-apt-repository 'deb [arch=amd64,arm64,ppc64el] http://ftp.osuosl.org/pub/mariadb/repo/10.3/ubuntu bionic main'
else
    warning "Sorry, this installation script only work for Ubuntu 14.04, 16.04 & 18.04 and Linux Mint 17, 18 & 19."
    exit 0
fi

# Add MariaDB source list from MariaDB repo configuration tool
if [ ! -f "/etc/apt/sources.list.d/MariaDB-${DISTRIB_REPO}.list" ]; then
touch /etc/apt/sources.list.d/MariaDB-${DISTRIB_REPO}.list
cat > /etc/apt/sources.list.d/MariaDB-${DISTRIB_REPO}.list <<EOL
# MariaDB ${MARIADB_VER} repository list - created 2019-04-26 08:58 UTC
# http://mariadb.org/mariadb/repositories/
deb [arch=${ARCH_REPO}] http://ftp.osuosl.org/pub/mariadb/repo/${MARIADB_VER}/ubuntu ${DISTRIB_REPO} main
deb-src http://ftp.osuosl.org/pub/mariadb/repo/${MARIADB_VER}/ubuntu ${DISTRIB_REPO} main
EOL
fi

# Add PHP (latest stable) from Ondrej's repo
# Source: https://launchpad.net/~ondrej/+archive/ubuntu/php

# Fix for NO_PUBKEY key servers error
run apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 4F4EA0AAE5267A6C
run add-apt-repository -y ppa:ondrej/php

echo "Updating repository and install required packages..."

# Update repos
run apt-get update -y

# Install pre-requirements
#python-software-properties
run apt-get install -y software-properties-common build-essential git unzip cron curl gnupg2 ca-certificates \
    lsb-release rsync libgd-dev libgeoip-dev libxslt1-dev libssl-dev libxml2-dev openssl snmp spawn-fcgi fcgiwrap geoip-database

status "Adding repositories completed..."

function create_swap() {
  echo "Enabling 1GiB swap..."
  L_SWAP_FILE="/lemper-swapfile"
  fallocate -l 1G $L_SWAP_FILE && \
  chmod 600 $L_SWAP_FILE && \
  chown root:root $L_SWAP_FILE && \
  mkswap $L_SWAP_FILE && \
  swapon $L_SWAP_FILE
}

function check_swap() {
  echo -e "\nChecking swap..."
  if free | awk '/^Swap:/ {exit !$2}'; then
    :
  else
    warning "No swap detected"
    create_swap
  fi
}

check_swap
