#!/usr/bin/env bash

# Certbot Let's Encrypt Uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 17/08/2019
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

function init_certbotle_removal() {
    if [[ -n $(dpkg-query -l | grep certbot | awk '/certbot/ { print $2 }') ]]; then
        echo "Found Certbot package installation. Removing..."

        # Remove Certbot.
        run apt-get --purge remove -y certbot

        if "${FORCE_REMOVE}"; then
            run add-apt-repository -y --remove ppa:certbot/certbot
        fi
    else
        echo "Certbot package not found, possibly installed from source."
        echo "Remove it manually."

        CERTBOT_BIN=$(command -v certbot)

        echo "Which certbot bin: ${CERTBOT_BIN}"
    fi

    # Remove Certbot config files.
    warning "!! This action is not reversible !!"
    while [[ "${REMOVE_CERTBOTCONF}" != "y" && "${REMOVE_CERTBOTCONF}" != "n" && "${AUTO_REMOVE}" != true ]]; do
        read -rp "Remove Certbot config and Let's Encrypt certificate files? [y/n]: " -e REMOVE_CERTBOTCONF
    done
    if [[ "${REMOVE_CERTBOTCONF}" == Y* || "${REMOVE_CERTBOTCONF}" == y* || "${FORCE_REMOVE}" == true ]]; then
        if [ -d /etc/letsencrypt ]; then
            run rm -fr /etc/letsencrypt
        fi
        echo "All your Certbot config and Let's Encrypt certificate files deleted permanently."
    fi

    # Final test.
    if "${DRYRUN}"; then
        warning "Certbot Let's Encrypt client removed in dryrun mode."
    else
        if [[ -z $(command -v certbot) ]]; then
            status "Certbot Let's Encrypt client removed succesfully."
        else
            warning "Unable to remove Certbot Let's Encrypt client."
        fi
    fi
}

echo "Uninstalling Certbot Let's Encrypt..."
if [[ -n $(command -v certbot) ]]; then
    while [[ "${REMOVE_CERTBOT}" != "y" && "${REMOVE_CERTBOT}" != "n" && "${AUTO_REMOVE}" != true ]]; do
        read -rp "Are you sure to remove Certbot Let's Encrypt client? [y/n]: " -e REMOVE_CERTBOT
    done
    if [[ "${REMOVE_CERTBOT}" == Y* || "${REMOVE_CERTBOT}" == y* || "${AUTO_REMOVE}" == true ]]; then
        init_certbotle_removal "$@"
    else
        echo "Found Certbot Let's Encrypt, but not removed."
    fi
else
    warning "Oops, Certbot Let's Encrypt installation not found."
fi
