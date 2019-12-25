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

if hash apt-get 2>/dev/null; then
    # Update repositories.
    echo "Updating repository..."
    run apt-get -qq update -y

    # Install dependencies.
    echo "Installing pre-requisite packages..."
    run apt-get -qq install -y apache2-utils apt-transport-https autoconf automake bash build-essential ca-certificates cmake cron \
        curl dnsutils gcc geoip-bin geoip-database git gnupg2 htop iptables libc-dev libcurl4-openssl-dev libgd-dev libgeoip-dev \
        libssl-dev libxml2-dev libpcre3-dev libxslt1-dev lsb-release make ntpdate openssh-server openssl pkg-config re2c rsync \
        software-properties-common sasl2-bin snmp sudo sysstat tar tzdata unzip wget whois zlib1g-dev
elif hash yum 2>/dev/null; then
    if [ "${VERSION_ID}" == "5" ]; then
        run yum -y update
        #yum -y localinstall $pkg --nogpgcheck
    else
        run yum -y update
	    #yum -y localinstall $pkg
    fi
else
    fail "Unable to install LEMPer, this GNU/Linux distribution is not supported."
fi

status "Required packages installation completed..."

# Configure server clock.
echo -e "\nReconfigure server clock..."

# Reconfigure timezone.
if [[ -n ${TIMEZONE} && ${TIMEZONE} != "none" ]]; then
    run bash -c "echo '${TIMEZONE}' > /etc/timezone"
    run rm -f /etc/localtime
    run dpkg-reconfigure -f noninteractive tzdata

    # Save config.
    save_config "TIMEZONE=${TIMEZONE}"
fi

# Update local time.
# Masked (?).
run systemctl unmask ntp.service
run service ntp stop
run ntpdate -s cn.pool.ntp.org
run service ntp start
