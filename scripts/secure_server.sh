#!/usr/bin/env bash

# Basic Server Security Hardening
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 01/07/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include decorator
if [ "$(type -t run)" != "function" ]; then
    . scripts/decorator.sh
fi

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    error "You need to be root to run this script"
    exit 1
fi

echo -e "\nWelcome to LEMPer Basic Security Hardening"

echo "Before starting, let's create a pair of keys that some hosts ask for during installation of the server.

On your local machine, open new terminal and create an SSH key pair using the ssh-keygen tool,
use the following command:

ssh-keygen -t rsa -b 4096

After this step, you will have the following files: id_rsa and id_rsa.pub (private and public keys).
Never share your private key."

read -t 15 -p "Press [Enter] to continue..." </dev/tty

echo -en "Open your public key (id_rsa.pub) file, copy paste the key here: "
read RSAPublicKey

# Give default account access
if [[ ! -z "$RSAPublicKey" ]]; then
    echo "\nSecuring your SSH server..."

    run mkdir /home/lemper/.ssh

# Create authorized_keys file and copy your public key here
cat > /home/lemper/.ssh/authorized_keys <<EOL
${RSAPublicKey}
EOL

    # Fix ownership and permission
    chown lemper /home/lemper/.ssh
    chown lemper /home/lemper/.ssh/authorized_keys
    chmod 700 /home/lemper/.ssh
    chmod 600 /home/lemper/.ssh/authorized_keys

    # Securing the SSH server
    sed -i "/^#Port 22/a Port\ 2269" /etc/ssh/sshd_config
    sed -i "/^#PermitRootLogin prohibit-password/a PermitRootLogin\ no" /etc/ssh/sshd_config
    sed -i "/^#PasswordAuthentication yes/a PasswordAuthentication\ no" /etc/ssh/sshd_config
    sed -i "/^#ClientAliveInterval 0/a ClientAliveInterval\ 600" /etc/ssh/sshd_config
    sed -i "/^#ClientAliveCountMax/a ClientAliveCountMax\ 3" /etc/ssh/sshd_config

    run service sshd restart
fi

### Install & Configure the Uncomplicated Firewall (UFW)
echo -en "Do you want to enable Iptables-based Firewall? [Y/n]: "
read enableUFW
if [[ "${enableUFW}" == Y* || "${enableUFW}" == y* ]]; then

    # Install UFW
    run apt-get install ufw

    # close all incoming ports
    run ufw default deny incoming

    # open all outgoing ports
    run ufw default allow outgoing

    # open SSH port
    run ufw allow 2269/tcp

    # open HTTP port
    run ufw allow 80
    run ufw allow 8082
    run ufw allow 8083

    # open HTTPS port
    run ufw allow 443
    run ufw allow 4042
    run ufw allow 4043

    # open MySQL port
    run ufw allow 3306

    # open SMTP port
    run ufw allow 25

    # open IMAPS
    run ufw allow 143
    run ufw allow 993

    # open POP3S
    run ufw allow 110
    run ufw allow 995

    # open DNS port
    run ufw allow 53

    # open ntp port : to sync the clock of your machine
    run ufw allow 123/udp

    # turn on firewall
    run ufw enable
fi

# Configure server clock
run dpkg-reconfigure tzdata
