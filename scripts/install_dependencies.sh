#!/usr/bin/env bash

# Dependencies Installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04 & 16.04
# Last Build        : 02/08/2019
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

echo "Updating repository and installing required packages..."

if hash apt-get 2>/dev/null; then
    # Update repositories.
    run apt-get -qq update -y

    # Install dependencies.
    run apt-get -qq install -y apache2-utils apt-transport-https bash build-essential ca-certificates cron curl \
        git gnupg2 iptables libgd-dev libgeoip-dev libssl-dev libxml2-dev libpcre3-dev libxslt1-dev lsb-release \
        openssh-server openssl rsync software-properties-common snmp sudo sysstat tar unzip wget whois
elif hash yum 2>/dev/null; then
    fail "Unable to install LEMPer: yum distribution is not supported yet."

    if [ "${VERSION_ID}" == "5" ]; then
        run yum -y update
        #yum -y localinstall $pkg --nogpgcheck
    else
        run yum -y update
	    #yum -y localinstall $pkg
    fi
else
    fail "Unable to install LEMPer: this Linux distribution is not dpkg/yum enabled."
fi

status "Installation required packages completed..."

# Configure server clock.
echo -e "\nReconfigure server clock..."
run dpkg-reconfigure tzdata
