#!/usr/bin/env bash

# Certbot Let's Encrypt Uninstaller
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

function init_certbotle_removal() {
    if dpkg-query -l | awk '/certbot/ { print $2 }' | grep -qwE "^certbot$"; then
        echo "Found Certbot package installation. Removing..."

        # Remove Certbot.
        run apt-get purge -qq -y certbot

        [[ "${FORCE_REMOVE}" == true ]] && \
            run add-apt-repository -y --remove ppa:certbot/certbot
    elif snap list | awk '/certbot/ { print $1 }' | grep -qwE "^certbot$"; then
        echo "Found Certbot snap installation. Removing..."

        # Remove Certbot.
        [ -x /usr/bin/certbot ] && run unlink /usr/bin/certbot
        [[ -n $(command -v snap) ]] && run snap remove certbot
    else
        echo "Certbot package not found, possibly installed from source."

        CERTBOT_BIN=$(command -v certbot)
        echo "Certbot binary executable: ${CERTBOT_BIN}"

        #run python -m pip uninstall certbot
    fi

    # Remove Certbot config files.
    echo "Removing certbot configuration..."
    warning "!! This action is not reversible !!"

    if [[ "${AUTO_REMOVE}" == true ]]; then
        if [[ ${FORCE_REMOVE} == true ]]; then
            REMOVE_CERTBOT_CONFIG="y"
        else
            REMOVE_CERTBOT_CONFIG="n"
        fi
    else
        while [[ "${REMOVE_CERTBOT_CONFIG}" != "y" && "${REMOVE_CERTBOT_CONFIG}" != "n" ]]; do
            read -rp "Remove configuration and certificate files? [y/n]: " -e REMOVE_CERTBOT_CONFIG
        done
    fi

    if [[ "${REMOVE_CERTBOT_CONFIG}" == Y* || "${REMOVE_CERTBOT_CONFIG}" == y* ]]; then
        [ -d /etc/letsencrypt ] && run rm -fr /etc/letsencrypt

        echo "All your configuration and certificate files deleted permanently."
    fi

    # Final test.
    if [[ "${DRYRUN}" != true ]]; then
        if [[ -z $(command -v certbot) ]]; then
            success "Certbot Let's Encrypt client removed succesfully."
        else
            info "Unable to remove Certbot Let's Encrypt client."
        fi
    else
        info "Certbot Let's Encrypt client removed in dry run mode."
    fi
}

echo "Uninstalling Certbot Let's Encrypt..."

if [[ -n $(command -v certbot) ]]; then
    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_CERTBOT="y"
    else
        while [[ "${REMOVE_CERTBOT}" != "y" && "${REMOVE_CERTBOT}" != "n" ]]; do
            read -rp "Are you sure to remove Certbot Let's Encrypt client? [y/n]: " -e REMOVE_CERTBOT
        done
    fi

    if [[ "${REMOVE_CERTBOT}" == y* || "${REMOVE_CERTBOT}" == Y* ]]; then
        init_certbotle_removal "$@"
    else
        echo "Found Certbot Let's Encrypt, but not removed."
    fi
else
    info "Oops, Certbot Let's Encrypt installation not found."
fi
