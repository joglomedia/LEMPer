#!/usr/bin/env bash

# Certbot Let's Encrypt Installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 12/07/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    . ${BASEDIR}/helper.sh
fi

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    error "You need to be root to run this script"
    exit 1
fi

echo ""
echo "Welcome to Certbot Let's Encrypt Installation..."
echo ""

function init_certbotle_install() {
    while [[ $INSTALL_CERTBOT != "y" && $INSTALL_CERTBOT != "n" ]]; do
        read -p "Do you want to install Certbot Let's Encrypt? [y/n]: " -e INSTALL_CERTBOT
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
        fi

        # Generate Diffie-Hellman parameters
        if [ ! -f /etc/letsencrypt/ssl-dhparam-4096.pem ]; then
            echo "Generating Diffie-Hellman parameters for enhanced security,"
            echo "This is going to take a long time"

            run openssl dhparam -out /etc/letsencrypt/ssl-dhparam-2048.pem 2048
            run openssl dhparam -out /etc/letsencrypt/ssl-dhparam-4096.pem 4096
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

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(which certbot) ]]; then
    warning "Certbot Let's Encrypt already exists. Installation skipped..."
else
    init_certbotle_install "$@"
fi
