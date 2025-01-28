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
    re2c rsync software-properties-common sasl2-bin snap snmp sqlite3 sudo sysstat tar tzdata unzip wget \
    whois xz-utils zlib1g-dev geoip-bin geoip-database gettext gettext-base libgeoip-dev libpthread-stubs0-dev uuid-dev

if [[ ! -d /root/.gnupg ]]; then
    run mkdir /root/.gnupg
fi

##
# Install Python custom version
##
function install_python_from_source() {
    local PYTHON_VERSION=${1}

    if [[ -z "${PYTHON_VERSION}" ]]; then
        PYTHON_VERSION=${DEFAULT_PYTHON_VERSION:-"3.13.0"}
    fi

    local CURRENT_DIR && \
        CURRENT_DIR=$(pwd)

    PYTHON_SRC="https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz"

    if curl -sLI "${PYTHON_SRC}" | grep -q "HTTP/[.12]* [2].."; then
        run run cd "${BUILD_DIR}" && \
        run curl -sSL -o "Python-${PYTHON_VERSION}.tgz" "${PYTHON_SRC}" && \
        run tar -xzf "Python-${PYTHON_VERSION}.tgz" && \
        run cd "Python-${PYTHON_VERSION}" && \
        run ./configure --enable-shared --enable-optimizations --prefix=/usr/local LDFLAGS="-Wl,--rpath=/usr/local/lib" && \
        run make altinstall && \
        run update-alternatives --install /usr/bin/python python /usr/local/bin/python3.13 313 && \
        run update-alternatives --set python /usr/local/bin/python3.13 && \
        run curl -sSL -o "get-pip.py" "https://bootstrap.pypa.io/get-pip.py" && \
        run python get-pip.py && \
        run python -m pip install --upgrade pip && \
        run cd "${CURRENT_DIR}" || return 1
    else
        error "Unable to download Python-${PYTHON_VERSION} source..."
    fi
}

# Install Python 3
echo "Installing Python 3 package..."

case "${DISTRIB_NAME}" in
    debian)
        case "${RELEASE_NAME}" in
            bookworm)
                run apt-get install -q -y python3-launchpadlib python3-pip python3-venv && \
                run update-alternatives --install /usr/bin/python python "$(command -v python3)" 3 && \
                run update-alternatives --set python /usr/bin/python3
            ;;
            buster | bullseye)
                # Install Python 3 from source.
                install_python_from_source "3.13.0"
            ;;
            *)
                fail "Unable to install Python dependencies, this GNU/Linux distribution is not supported."
            ;;
        esac
    ;;
    ubuntu)
        # Install Python
        # python3.7 will be dropped on next Certbot release
        # deadsnake ppa only support Focal, Jammy & Noble
        case "${RELEASE_NAME}" in
            noble | focal | jammy)
                run add-apt-repository ppa:deadsnakes/ppa -y && \
                run apt-get update -q -y && \
                run apt-get install -q -y python3.13 python3.13-dev python3.13-venv && \
                run update-alternatives --install /usr/bin/python python "$(command -v python3.13)" 313 && \
                run update-alternatives --set python /usr/bin/python3.13
            ;;
            bionic)
                # Install Python 3 from source.
                install_python_from_source "3.13.0"
            ;;
            *)
                fail "Unable to install Python dependencies, this GNU/Linux distribution is not supported."
            ;;
        esac
    ;;
esac

# Self-signed OpenSSL cert config.
echo "Add self-signed SSL config".
run mkdir -p "/etc/lemper/ssl/${HOSTNAME}" && \
run cp -f etc/openssl/ca.conf /etc/lemper/ssl/ca.conf && \
run cp -f etc/openssl/csr.conf /etc/lemper/ssl/csr.conf && \
run cp -f etc/openssl/cert.conf /etc/lemper/ssl/cert.conf

# Update locale config.
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
