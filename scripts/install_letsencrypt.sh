#!/usr/bin/env bash

# Certbot Let's Encrypt installer
# Min requirement   : GNU/Linux Ubuntu 14.04
# Last Build        : 09/09/2017
# Author            : MasEDI.Net (hi@masedi.net)

# Include decorator
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    . ${BASEDIR}/decorator.sh
fi

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    error "This script must be run as root..."
    exit 1
fi

clear
echo "+=========================================================================+"
echo "+  Certbot Let's Encrypt Installer for Ubuntu VPS,  Written by ESLabs.ID  +"
echo "+=========================================================================+"
echo "+     A small tool to install Certbot & Let's Enscrypt SSL certificate    +"
echo "+                                                                         +"
echo "+       For more information please visit https://ngxtools.eslabs.id      +"
echo "+=========================================================================+"
sleep 1

run add-apt-repository ppa:certbot/certbot
run apt-get update
run apt-get install certbot

# Add this certbot renew command to cron
#15 3 * * * /usr/bin/certbot renew --quiet --renew-hook "/bin/systemctl reload nginx"

croncmd='/usr/bin/certbot renew --quiet --renew-hook "/bin/systemctl reload nginx"'
cronjob="15 3 * * * $croncmd"
crontab -l | sudo fgrep -v -F "$croncmd" | { sudo cat; sudo echo "$cronjob"; } | sudo crontab -
