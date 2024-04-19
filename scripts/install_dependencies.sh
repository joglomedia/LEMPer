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
    . "${BASE_DIR}/utils.sh"

    # Make sure only root can run this installer script.
    requires_root "$@"

    # Make sure only supported distribution can run this installer script.
    preflight_system_check
fi

echo "Installing required dependencies..."

DISTRIB_NAME=${DISTRIB_NAME:-$(get_distrib_name)}
RELEASE_NAME=${RELEASE_NAME:-$(get_release_name)}

# Fix broken install, first?
if [[ "${FIX_BROKEN_INSTALL}" == true ]]; then
    echo "Trying fix broken package install.."
    run apt-get clean
    run dpkg --configure -a
    run apt-get install -q -y --fix-broken
fi

# Update repositories.
echo "Updating repository, please wait..."
run apt-get update -q -y && \
run apt-get upgrade -q -y

# Install dependencies.
echo "Installing packages, be patient..."
run apt-get install -q -y \
    apt-transport-https apt-utils autoconf automake bash bc build-essential ca-certificates \
    cmake cron curl dmidecode dnsutils gcc gdb git gnupg2 htop iptables libc-bin libc6-dev \
    libcurl4-openssl-dev libgpgme11-dev libssl-dev libpcre3-dev libxml2-dev libxslt1-dev \
    libtool locales logrotate lsb-release make net-tools openssh-server openssl pkg-config \
    re2c rsync software-properties-common sasl2-bin snap snmp sudo sysstat tar tzdata unzip wget \
    whois xz-utils zlib1g-dev geoip-bin geoip-database gettext libgeoip-dev libpthread-stubs0-dev uuid-dev

# Install Python 3
echo "Installing Python..."

case "${DISTRIB_NAME}" in
    debian)
        case "${RELEASE_NAME}" in
            bookworm)
                run apt-get install -q -y python3-launchpadlib python3-pip python3-venv && \
                run update-alternatives --install /usr/bin/python python "$(command -v python3)" 3 && \
                run update-alternatives --set python /usr/bin/python3
            ;;
            *)
                # Add deadsnakes repository.
                case "${RELEASE_NAME}" in
                    buster | bullseye)
                        DEADSNAKES_PPA="focal"
                    ;;
                esac

                run touch "/etc/apt/sources.list.d/deadsnakes-ppa-ubuntu-${DEADSNAKES_PPA}.list" && \
                run bash -c "echo 'deb https://ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu ${DEADSNAKES_PPA} main' > /etc/apt/sources.list.d/deadsnakes-ppa-ubuntu-${DEADSNAKES_PPA}.list" && \
                run bash -c "echo 'deb-src https://ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu ${DEADSNAKES_PPA} main' >> /etc/apt/sources.list.d/deadsnakes-ppa-ubuntu-${DEADSNAKES_PPA}.list" && \
                run apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys F23C5A6CF475977595C89F51BA6932366A755776

                run apt-get update -q -y && \
                run apt-get install -q -y python3.7 python3.7-dev python3.7-venv \
                    python3.9 python3.9-dev python3.9-venv python3-pip && \
                run update-alternatives --install /usr/bin/python python "$(command -v python3.7)" 37 && \
                run update-alternatives --install /usr/bin/python python "$(command -v python3.9)" 39 && \
                run update-alternatives --set python /usr/bin/python3.7
            ;;
        esac
    ;;
    ubuntu)
        # Install Python
        run add-apt-repository ppa:deadsnakes/ppa -y && \
        run apt-get update -q -y && \
        run apt-get install -q -y python3.7 python3.7-dev python3.7-venv \
            python3.9 python3.9-dev python3.9-venv python3-pip && \
        run update-alternatives --install /usr/bin/python python "$(command -v python3.7)" 37 && \
        run update-alternatives --install /usr/bin/python python "$(command -v python3.9)" 39 && \
        run update-alternatives --set python /usr/bin/python3.7
    ;;
esac

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
