#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Shared Security Helpers                                          |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2026 MasEDI.Net (https://masedi.net/lemper)          |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@lemper.cloud so we can send you a copy immediately.          |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <me@masedi.net>                                |
# +-------------------------------------------------------------------------+


function core_get_distrib_name() {
    if [ -f /etc/os-release ]; then
        # Export os-release vars.
        # shellcheck disable=SC1091
        . /etc/os-release

        # Export lsb-release vars.
        # shellcheck disable=SC1091
        [ -f /etc/lsb-release ] && . /etc/lsb-release

        # Get distribution name.
        if [[ "${ID_LIKE:-}" == "ubuntu" ]]; then
            DISTRIB_NAME="ubuntu"
        else
            DISTRIB_NAME=${ID:-"unsupported"}
        fi
    elif [[ -e /etc/system-release ]]; then
        DISTRIB_NAME="unsupported"
    else
        # Red Hat /etc/redhat-release
        DISTRIB_NAME="unsupported"
    fi

    echo "${DISTRIB_NAME}"
}

function core_ubuntu_release_codename() {
    case "${1:-}" in
        22.04 | LM21) printf 'jammy\n' ;;
        24.04 | LM22) printf 'noble\n' ;;
        26.04) printf 'resolute\n' ;;
        *) printf 'unsupported\n' ;;
    esac
}

function core_get_release_name() {
    if [ -f /etc/os-release ]; then
        # Export os-release vars.
        # shellcheck disable=SC1091
        . /etc/os-release

        # Export lsb-release vars.
        # shellcheck disable=SC1091
        [ -f /etc/lsb-release ] && . /etc/lsb-release

        # Get distribution name.
        if [[ "${ID_LIKE:-}" == "ubuntu" ]]; then
            DISTRIB_NAME="ubuntu"
        else
            DISTRIB_NAME=${ID:-"unsupported"}
        fi

        # Get distribution release / version ID.
        DISTRIB_VERSION=${VERSION_ID:-"${DISTRIB_RELEASE:-}"}
        MAJOR_RELEASE_VERSION=$(echo "${DISTRIB_VERSION}" | awk -F. '{print $1}')

        case ${DISTRIB_NAME} in
            debian)
                RELEASE_NAME=${VERSION_CODENAME:-"unsupported"}

                # TODO for Debian install
                case ${MAJOR_RELEASE_VERSION} in
                    10)
                        RELEASE_NAME="buster"
                    ;;
                    11)
                        RELEASE_NAME="bullseye"
                    ;;
                    12)
                        RELEASE_NAME="bookworm"
                    ;;
                    *)
                        RELEASE_NAME="unsupported"
                    ;;
                esac
            ;;
            ubuntu)
                # Hack for Linux Mint release number.
                [[ "${DISTRIB_ID:-}" == "LinuxMint" || "${ID:-}" == "linuxmint" ]] && \
                    DISTRIB_RELEASE="LM${MAJOR_RELEASE_VERSION}"

                # os-release is available even when lsb-release is absent.
                if [[ "${ID:-}" == linuxmint || "${DISTRIB_ID:-}" == LinuxMint ]]; then
                    RELEASE_NAME=$(core_ubuntu_release_codename "${DISTRIB_RELEASE}")
                else
                    RELEASE_NAME=$(core_ubuntu_release_codename "${DISTRIB_VERSION}")
                fi
            ;;
            *)
                RELEASE_NAME="unsupported"
            ;;
        esac
    elif [ -f /etc/system-release ]; then
        RELEASE_NAME="unsupported"
    else
        # Red Hat /etc/redhat-release
        RELEASE_NAME="unsupported"
    fi

    echo "${RELEASE_NAME}"
}

function core_get_release_version() {
    if [ -f /etc/os-release ]; then
        # Export os-release vars.
        # shellcheck disable=SC1091
        . /etc/os-release

        # Export lsb-release vars.
        # shellcheck disable=SC1091
        [ -f /etc/lsb-release ] && . /etc/lsb-release

        # Get distribution release / version ID.
        RELEASE_VERSION=${VERSION_ID:-"${DISTRIB_RELEASE:-0.0}"}
    elif [ -f /etc/system-release ]; then
        RELEASE_VERSION="0.0"
    else
        # Red Hat /etc/redhat-release
        RELEASE_VERSION="0.0"
    fi

    echo "${RELEASE_VERSION}"
}

function core_get_distrib_arch() {
    local ARCH=${ARCH:-$(uname -p)}
    local DISTRIB_ARCH

    case "${ARCH}" in
        i386 | i486| i586 | i686)
            DISTRIB_ARCH="386"
        ;;
        x86_64 | amd64)
            DISTRIB_ARCH="amd64"
        ;;
        arm64 | aarch* | armv8*)
            DISTRIB_ARCH="arm64"
        ;;
        arm | armv7*)
            DISTRIB_ARCH="armv6l"
        ;;
        *)
            DISTRIB_ARCH="386"
        ;;
    esac

    echo "${DISTRIB_ARCH}"
}

function get_distrib_name() {
    core_get_distrib_name
}

function get_release_name() {
    core_get_release_name
}

function get_release_version() {
    core_get_release_version
}

function get_distrib_arch() {
    core_get_distrib_arch
}
