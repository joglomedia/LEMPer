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

if hash apt 2>/dev/null; then
    # Update repositories.
    echo "Updating repository..."
    run apt update -qq -y && \
    run apt upgrade -qq -y

    # Install dependencies.
    echo -e "\nInstalling pre-requisites/dependencies package..."
    install_dependencies "apt install -qq -y" debian_is_installed \
        apt-transport-https apt-utils autoconf automake bash build-essential ca-certificates cmake cron \
        curl dnsutils gcc geoip-bin geoip-database git gnupg2 htop iptables libc-dev libcurl4-openssl-dev libgd-dev libgeoip-dev \
        libssl-dev libxml2-dev libpcre3-dev libtool libxslt1-dev lsb-release make ntp ntpstat openssh-server openssl pkg-config \
        re2c rsync software-properties-common sasl2-bin snmp sudo sysstat tar tzdata unzip wget whois zlib1g-dev

    # Configure server clock.
    echo -e "\nReconfigure server clock..."

    # Reconfigure timezone.
    if [[ -n ${TIMEZONE} && ${TIMEZONE} != "none" ]]; then
        run bash -c "echo '${TIMEZONE}' > /etc/timezone"
        run rm -f /etc/localtime
        run dpkg-reconfigure -f noninteractive tzdata

        # Sync and update local time with ntpd.
        # Masked? unmask first.
        run systemctl unmask ntp.service
        run systemctl start ntp

        # Save config.
        save_config "TIMEZONE=${TIMEZONE}"
    fi

    # Verify system pre-requisites.
    verify_prerequisites
else
    fail "Unable to install LEMPer, this GNU/Linux distribution is not supported."
fi

echo ""
success "Required packages installation completed..."
