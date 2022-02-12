#!/usr/bin/env bash

# Dependencies Installer
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 12/02/2022
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/helper.sh"

    # Make sure only root can run this installer script.
    requires_root "$@"

    # Make sure only supported distribution can run this installer script.
    preflight_system_check
fi

echo "Installing required dependencies..."

# Fix broken install, first?
if [[ "${FIX_BROKEN_INSTALL}" == true ]]; then
    run dpkg --configure -a
    run apt-get install -qq -y --fix-broken
fi

# Update repositories.
echo "Updating repository, please wait..."
run apt-get update -qq -y && \
run apt-get upgrade -qq -y

# Install dependencies.
echo "Installing packages, be patient..."
run apt-get install -qq -y \
    apt-transport-https apt-utils autoconf automake bash build-essential ca-certificates \
    cmake cron curl dmidecode dnsutils gcc geoip-bin geoip-database gettext git gnupg2 \
    htop iptables libc-bin libc6-dev libcurl4-openssl-dev libgd-dev libgeoip-dev libgpgme11-dev \
    libsodium-dev libssl-dev libxml2-dev libpcre3-dev libtool libxslt1-dev locales logrotate lsb-release \
    make net-tools openssh-server openssl pkg-config python python3 re2c rsync software-properties-common \
    sasl2-bin sendmail snmp sudo sysstat tar tzdata unzip wget whois xz-utils zlib1g-dev

# Update locale
echo "Reconfigure locale..."

run locale-gen --purge en_US.UTF-8 id_ID.UTF-8

# Attended locales reconfiguration causing Terraform provisioning stuck.
if [[ "${AUTO_INSTALL}" != true ]]; then
    run dpkg-reconfigure locales
fi

# Configure server clock.
echo "Reconfigure server clock..."

# Reconfigure timezone.
if [[ -n ${TIMEZONE} && ${TIMEZONE} != "none" ]]; then
    run bash -c "echo '${TIMEZONE}' > /etc/timezone"
    run rm -f /etc/localtime
    run dpkg-reconfigure -f noninteractive tzdata

    # Save config.
    save_config "TIMEZONE=${TIMEZONE}"
fi

success "Required packages installation completed..."
