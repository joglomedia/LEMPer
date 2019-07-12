#!/usr/bin/env bash

# Certbot Let's Encrypt installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 12/07/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include decorator
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
while [[ $INSTALL_CERTBOT != "y" && $INSTALL_CERTBOT != "n" ]]; do
    read -p "Do you want to install Certbot Let's Encrypt SSL? [y/n]: " -e INSTALL_CERTBOT
done

if [[ "${INSTALL_CERTBOT}" == Y* || "${INSTALL_CERTBOT}" == y* ]]; then
    echo -e "\nInstalling Certbot Let's Encrypt SSL..."

    if [[ ! -n $(which certbot) ]]; then
        run add-apt-repository -y ppa:certbot/certbot >> lemper.log 2>&1
        run apt-get -y update >> lemper.log 2>&1
        run apt-get -y install certbot >> lemper.log 2>&1

        # Add this certbot renew command to cron
        #15 3 * * * /usr/bin/certbot renew --quiet --renew-hook "/bin/systemctl reload nginx"

        croncmd='15 3 * * * /usr/bin/certbot renew --quiet --renew-hook "/usr/sbin/service nginx reload -s"'
        crontab -l > mycronjob
        echo "$croncmd" >> mycronjob
        crontab mycronjob
        rm -f mycronjob
    else
        echo -e "Certbot Let's Encrypt already installed"
    fi

    # Generate Diffie-Hellman parameter
    if [ ! -f /etc/letsencrypt/ssl-dhparam-4096.pem ]; then
        echo "Generating Diffie-Hellman parameter for enhanced security..."

        #openssl dhparam -out /etc/letsencrypt/ssl-dhparam-2048.pem 2048
        openssl dhparam -out /etc/letsencrypt/ssl-dhparam-4096.pem 4096
    fi
fi
