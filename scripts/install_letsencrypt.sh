#!/usr/bin/env bash

# Certbot Let's Encrypt installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 01/07/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include decorator
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    . ${BASEDIR}/decorator.sh
fi

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    error "You need to be root to run this script"
    exit 1
fi

echo -en "\nDo you want to install Certbot Let's Encrypt? [Y/n]: "
read certbotInstall

if [[ "${certbotInstall}" == Y* || "${certbotInstall}" == y* ]]; then
    echo -e "\nInstalling Certbot Let's Encrypt..."

    if [[ ! -n $(which certbot) ]]; then
        run add-apt-repository -y ppa:certbot/certbot
        run apt-get -y update
        run apt-get -y install certbot

        # Add this certbot renew command to cron
        #15 3 * * * /usr/bin/certbot renew --quiet --renew-hook "/bin/systemctl reload nginx"

        croncmd='/usr/bin/certbot renew --quiet --renew-hook "/usr/sbin/service nginx reload -s"'
        cronjob="15 3 * * * $croncmd"
        crontab -l | sudo fgrep -v -F "$croncmd" | { sudo cat; sudo echo "$cronjob"; } | sudo crontab -
    else
        echo -e "Certbot Let's Encrypt already installed"
    fi

    # Generate Diffie-Hellman parameters
    if [ ! -f /etc/letsencrypt/ssl-dhparams-4096.pem ]; then
        echo "Generating Diffie-Hellman parameters for enhanced security..."

        #openssl dhparam -out /etc/letsencrypt/ssl-dhparams-2048.pem 2048
        #openssl dhparam -out /etc/letsencrypt/ssl-dhparams-4096.pem 4096
    fi
fi
