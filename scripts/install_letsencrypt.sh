#!/usr/bin/env bash

# Certbot Let's Encrypt Installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 12/07/2019
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

# Install Certbot Let's Encrypt.
function init_certbotle_install() {

    while [[ "${INSTALL_CERTBOT}" != "y" && "${INSTALL_CERTBOT}" != "n" ]]; do
        read -rp "Do you want to install Certbot Let's Encrypt? [y/n]: " -e INSTALL_CERTBOT
    done
    if [[ "${INSTALL_CERTBOT}" == Y* || "${INSTALL_CERTBOT}" == y* ]]; then
        echo -e "\nInstalling Certbot Let's Encrypt client..."

        run add-apt-repository -y ppa:certbot/certbot
        run apt-get -y update
        run apt-get -y install certbot

        # Add Certbot auto renew command to cron
        #15 3 * * * /usr/bin/certbot renew --quiet --renew-hook "/bin/systemctl reload nginx"

        if "${DRYRUN}"; then
            status "Add Certbot auto-renew to cronjob in dryrun mode."
        else
            export EDITOR=nano
            CRONCMD='15 3 * * * /usr/bin/certbot renew --quiet --renew-hook "/usr/sbin/service nginx reload -s"'
            touch lemper.cron
            crontab -u root lemper.cron
            crontab -l > lemper.cron

            if ! grep -qwE "/usr/bin/certbot\ renew" lemper.cron; then
                cat >> lemper.cron <<EOL
# LEMPer Cronjob
# Certbot Auto-renew Let's Encrypt certificates
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

${CRONCMD}
EOL

                crontab lemper.cron
                rm -f lemper.cron
            fi

            # Register a new account
            LE_EMAIL=${ADMIN_EMAIL:-"cert@lemper.sh"}
            run certbot register --email "${LE_EMAIL}" --no-eff-email
            #run certbot rupdate_account --email "${LE_EMAIL}" --no-eff-email
        fi

        if "${DRYRUN}"; then
            status -e "\nCertbot installed in dryrun mode."
        else
            if certbot --version | grep -q "certbot"; then
                status -e "\nCertbot installed successfully."
            else
                warning -e "\nSomething wrong with Certbot installation."
            fi
        fi
    fi
}

echo "[Welcome to Certbot Let's Encrypt Installer]"
echo ""

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v certbot) ]]; then
    warning "Certbot Let's Encrypt already exists. Installation skipped..."
else
    init_certbotle_install "$@"
fi
