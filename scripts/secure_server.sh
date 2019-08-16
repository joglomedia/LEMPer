#!/usr/bin/env bash

# Basic Server Security Hardening
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 01/07/2019
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

# Securing SSH server.
function securing_ssh() {
    #SSH_PASSWORDLESS=${SSH_PASSWORDLESS:-true}
    if "${SSH_PASSWORDLESS}"; then
        echo "
Before starting, let's create a pair of keys that some hosts ask for during installation of the server.

On your local machine, open new terminal and create an SSH key pair using the ssh-keygen tool,
use the following command:

ssh-keygen -t rsa -b ${HASH_LENGTH}

After this step, you will have the following files: id_rsa and id_rsa.pub (private and public keys).
Never share your private key.
"

        read -rt 60 -p "Press [Enter] to continue..." </dev/tty
        echo ""

        RSA_PUB_KEY=${RSA_PUB_KEY:-n}
        while ! [[ ${RSA_PUB_KEY} =~ ssh-rsa* ]]; do
            echo "Open your public key (id_rsa.pub) file,"
            read -rp "copy paste the key here: " -e RSA_PUB_KEY
        done

        # Grand access to SSH with key.
        if [[ ${RSA_PUB_KEY} =~ ssh-rsa* ]]; then
            echo -e "\nSecuring your SSH server with public key..."

            if [ ! -d /home/lemper/.ssh ]; then
                run mkdir /home/lemper/.ssh
            fi

            if [ ! -f /home/lemper/.ssh/authorized_keys ]; then
                run touch /home/lemper/.ssh/authorized_keys
            fi

            # Create authorized_keys file and copy your public key here.
            if "${DRYRUN}"; then
                echo "RSA public key added in dryrun mode."
            else
                cat >> /home/lemper/.ssh/authorized_keys <<EOL
${RSA_PUB_KEY}
EOL
                status "RSA public key added to the authorized_keys."
            fi

            # Fix authorized_keys file ownership and permission.
            run chown -hR lemper /home/lemper/.ssh
            run chmod 700 /home/lemper/.ssh
            run chmod 600 /home/lemper/.ssh/authorized_keys

            echo -e "\nEnable SSH_PASSWORDLESS login..."
            # Restrict root login directly, use sudo user instead.
            SSH_ROOT_LOGIN=${SSH_ROOT_LOGIN:-false}
            if ! ${SSH_ROOT_LOGIN}; then
                if grep -qwE "^PermitRootLogin\ [a-z]*" /etc/ssh/sshd_config; then
                    run sed -i "s/^PermitRootLogin\ [a-z]*/PermitRootLogin\ no/g" /etc/ssh/sshd_config
                else
                    run sed -i "/^#PermitRootLogin/a PermitRootLogin\ no" /etc/ssh/sshd_config
                fi
            fi

            # Disable password authentication for password-less login using key.
            if grep -qwE "^PasswordAuthentication\ [a-z]*" /etc/ssh/sshd_config; then
                run sed -i "s/^PasswordAuthentication\ [a-z]*/PasswordAuthentication\ no/g" /etc/ssh/sshd_config
            else
                run sed -i "/^#PasswordAuthentication/a PasswordAuthentication\ no" /etc/ssh/sshd_config
            fi

            if grep -qwE "^ClientAliveInterval\ [0-9]*" /etc/ssh/sshd_config; then
                run sed -i "s/^ClientAliveInterval\ [0-9]*/ClientAliveInterval\ 600/g" /etc/ssh/sshd_config
            else
                run sed -i "/^#ClientAliveInterval/a ClientAliveInterval\ 600" /etc/ssh/sshd_config
            fi

            if grep -qwE "^ClientAliveCountMax\ [0-9]*" /etc/ssh/sshd_config; then
                run sed -i "s/^ClientAliveCountMax\ [0-9]*/ClientAliveCountMax\ 3/g" /etc/ssh/sshd_config
            else
                run sed -i "/^#ClientAliveCountMax/a ClientAliveCountMax\ 3" /etc/ssh/sshd_config
            fi
        fi
    fi

    # Securing the SSH server.
    echo "Securing your SSH server with custom port..."
    SSH_PORT=${SSH_PORT:-n}
    while ! [[ ${SSH_PORT} =~ ^[0-9]+$ ]]; do
        read -rp "SSH Port (LEMPer default SSH port sets to 2269): " -i 2269 -e SSH_PORT
    done

    if [[ ${SSH_PORT} =~ ^[0-9]+$ ]]; then
        if grep -qwE "^Port\ [0-9]*" /etc/ssh/sshd_config; then
            run sed -i "s/^Port\ [0-9]*/Port\ ${SSH_PORT}/g" /etc/ssh/sshd_config
        else
            run sed -i "/^#Port\ [0-9]*/a Port\ ${SSH_PORT}" /etc/ssh/sshd_config
        fi

        status "SSH port updated to ${SSH_PORT}."
    else
        warning "Unable to update SSH port."
    fi

    # Restart SSH service after LEMPer installation completed.
    #run service sshd restart
}

# Install & Configure the Uncomplicated Firewall (UFW)
function install_ufw() {
    SSH_PORT=${1:-$SSH_PORT}

    echo -e "\nInstalling Uncomplicated Firewall (UFW)...\n"

    if [[ -n $(command -v apf) ]]; then
        # Remove APF+BFD if exists.
        remove_apf
    fi

    if [[ -n $(command -v csf) ]]; then
        # Remove CSF+LFD if exists.
        remove_csf
    fi

    # Install UFW
    run apt-get install -y ufw

    if [[ -n $(command -v ufw) ]]; then
        echo "Configuring UFW firewall rules..."

        # Close all incoming ports.
        run ufw default deny incoming

        # Open all outgoing ports.
        run ufw default allow outgoing

        # Open SSH port.
        run ufw allow "${SSH_PORT}/tcp"

        # Open HTTP port.
        run ufw allow 80
        run ufw allow 8082
        run ufw allow 8083

        # Open HTTPS port.
        run ufw allow 443
        run ufw allow 8443

        # Open MySQL port.
        run ufw allow 3306

        # Open SMTP port.
        run ufw allow 25

        # Open IMAPS ports.
        run ufw allow 143
        run ufw allow 993

        # Open POP3S ports.
        run ufw allow 110
        run ufw allow 995

        # Open DNS port.
        run ufw allow 53

        # Open ntp port : to sync the clock of your machine.
        run ufw allow 123/udp

        # Turn on firewall.
        run ufw enable

        # Restart
        if "${DRYRUN}"; then
            echo "UFW firewall installed in dryrun mode."
        else
            if service ufw restart; then
                status "UFW firewall installed successfully."
            else
                warning "Something wrong with UFW installation."
            fi
        fi
    fi
}

# Install & Configure the ConfigServer Security & Firewall (CSF)
function install_csf() {
    SSH_PORT=${1:-$SSH_PORT}

    echo -e "\nInstalling CSF+LFD firewall...\n"

    if [[ -n $(command -v ufw) ]]; then
        # Remove default Ubuntu firewall (UFW) if exists.
        remove_ufw
    fi

    if [[ -n $(command -v apf) ]]; then
        # Remove APF+BFD if exists.
        remove_apf
    fi

    # Install requirements.
    echo "Installing requirement packages..."

    if [[ -n $(command -v cpan) ]]; then
        run cpan -i "LWP LWP::Protocol::https GD::Graph IO::Socket::INET6"
    else
        run apt-get -y install libwww-perl liblwp-protocol-https-perl \
            libgd-graph-perl libio-socket-inet6-perl
    fi

    echo "Installing CSF+LFD firewall..."
    run wget -q https://download.configserver.com/csf.tgz
    run tar -xzf csf.tgz
    run cd csf/
    run sh install.sh
    run cd ../

    run perl /usr/local/csf/bin/csftest.pl

    if [ ! -f /etc/csf/csf.conf ]; then
        echo "Configuring CSF+LFD firewall rules..."

        # Enable CSF.
        run sed -i 's/^TESTING\ =\ "1"/TESTING\ =\ "0"/g' /etc/csf/csf.conf

        # Allowed incoming TCP ports.
        run sed -i "s/^TCP_IN\ =\ \"[0-9_,]*\"/TCP_IN\ =\ \"20,21,25,53,80,110,143,443,465,587,993,995,8081,8082,8083,8443,${SSH_PORT}\"/g" /etc/csf/csf.conf

        # Allowed outgoing TCP ports.
        run sed -i "s/^TCP_OUT\ =\ \"[0-9_,]*\"/TCP_OUT\ =\ \"20,21,25,53,80,110,143,443,465,587,993,995,8081,8082,8083,8443,${SSH_PORT}\"/g" /etc/csf/csf.conf

        # IPv6 support (requires ip6tables).
        if [[ -n $(command -v ip6tables) ]]; then
            ip6tables_version=$(ip6tables --version | grep 'v' | cut -d'v' -f2)
            if ! version_older_than "${ip6tables_version}" "1.4.3"; then
                echo "Configuring CSF+LFD for IPv6..."

                # Enable IPv6 support.
                run sed -i 's/^IPV6\ =\ "0"/IPV6\ =\ "1"/g' /etc/csf/csf.conf

                # Allowed incoming TCP ports for IPv6.
                run sed -i "s/^TCP6_IN\ =\ \"[0-9_,]*\"/TCP6_IN\ =\ \"20,21,25,53,80,110,143,443,465,587,993,995,8081,8082,8083,8443,${SSH_PORT}\"/g" /etc/csf/csf.conf

                # Allowed outgoing TCP ports for IPv6.
                run sed -i "s/^TCP6_OUT\ =\ \"[0-9_,]*\"/TCP6_OUT\ =\ \"20,21,25,53,80,110,143,443,465,587,993,995,8081,8082,8083,8443,${SSH_PORT}\"/g" /etc/csf/csf.conf
            else
                warning "ip6tables version greater than 1.4.3 required for IPv6 support."
            fi
        fi
    fi

    # Clean up installation files.
    run rm -fr csf/

    if "${DRYRUN}"; then
        echo "CSF+LFD firewall installed in dryrun mode."
    else
        if [[ -n $(command -v csf) && -n $(command -v lfd) ]]; then
            if service csf restart; then
                status "CSF firewall installed successfully. Starting now..."
            else
                warning "Something wrong with CSF installation."
            fi

            if service lfd restart; then
                status "LFD firewall installed successfully. Starting now..."
            else
                warning "Something wrong with LFD installation."
            fi
        else
            warning "Something wrong with CSF+LFD installation."
        fi
    fi
}

# Install & Configure the Advancef Policy Firewall (APF)
function install_apf() {
    SSH_PORT=${1:-$SSH_PORT}
    APF_VERSION="1.7.6-1"

    echo -e "\nInstalling APF+BFD iptables firewall...\n"

    if [[ -n $(command -v ufw) ]]; then
        # Remove default Ubuntu firewall (UFW) if exists.
        remove_ufw
    fi

    if [[ -n $(command -v csf) ]]; then
        # Remove CSF+LFD if exists.
        remove_csf
    fi

    echo "Installing APF+BFD firewall..."
    run wget -q --no-check-certificate https://github.com/rfxn/advanced-policy-firewall/archive/${APF_VERSION}.tar.gz \
        -O apf.tar.gz
    run tar -xf apf.tar.gz
    run cd advanced-policy-firewall-*/
    run bash install.sh
    run cd ../

    if [ ! -f /etc/apf/conf.apf ]; then
        echo "Configuring APF+BFD firewall rules..."

        # Enable APF.
        run sed -i "s/^DEVEL_MODE=\"1\"/DEVEL_MODE=\"0\"/g" /etc/apf/conf.apf

        # Get ethernet interface.
        IFACE=${IFACE:-$(find /sys/class/net -type l | grep -e "enp\|eth0" | cut -d'/' -f5)}

        # Set ethernet interface to monitor.
        run sed -i "s/^IFACE_UNTRUSTED=\"[0-9a-zA-Z]*\"/IFACE_UNTRUSTED=\"${IFACE}\"/g" /etc/apf/conf.apf

        # Enable fast load.
        run sed -i 's/^SET_FASTLOAD="0"/SET_FASTLOAD="1"/g' /etc/apf/conf.apf
    fi

    # Clean up installation files.
    run rm -fr advanced-policy-firewall-*/

    if "${DRYRUN}"; then
        echo "APF+BFD firewall installed in dryrun mode."
    else
        if [[ -n $(command -v apf) ]]; then
            if service apf restart; then
                status "APF firewall installed successfully. Starting now..."
            else
                warning "Something wrong with APF installation."
            fi
        else
            warning "Something wrong with APF installation."
        fi
    fi
}

function remove_ufw() {
    if [[ -n $(command -v ufw) ]]; then
        echo "Found UFW iptables firewall, trying to remove it..."

        run service ufw stop
        run ufw disable

        echo "Removing UFW iptables firewall..."

        run apt-get -y remove ufw
    fi
}

function remove_csf() {
    if [[ -n $(command -v csf) || -f /usr/lib/systemd/system/csf.service ]]; then
        echo "Found CSF+LFD iptables firewall, trying to remove it..."

        if [[ -f /etc/csf/uninstall.sh ]]; then
            run sh /etc/csf/uninstall.sh
        fi
    fi
}

function remove_apf() {
    if [[ -n $(command -v apf) && -f /etc/apf/conf.apf ]]; then
        echo "Found APF+BFD iptables firewall, trying to remove it..."

        run service apf stop
        run service iptables stop

        echo "Removing APF+BFD iptables firewall..."

        run rm -rf /etc/apf
        run rm -f /etc/cron.daily/fw
        run rm -f /etc/init.d/apf
        run rm -f /usr/local/sbin/apf
        run rm -f /usr/local/sbin/fwmgr
    fi
}

# Install Firewall.
function install_firewall() {
    echo ""
    echo "[Welcome to Iptables-based Firewall Installer]"
    echo ""
    warning "You should not run any other iptables firewall configuration script.
Any other iptables based firewall will be removed otherwise they will conflict."
    echo ""
    
    if "${AUTO_INSTALL}"; then
        DO_INSTALL_FW="y"
    fi
    while [[ ${DO_INSTALL_FW} != "y" && ${DO_INSTALL_FW} != "n" && "${AUTO_INSTALL}" != true ]]; do
        read -rp "Do you want to install Firewall configurator? [y/n]: " -i y -e DO_INSTALL_FW
    done

    if [[ "${DO_INSTALL_FW}" == y* && "${INSTALL_FW}" == true ]]; then

        if "${AUTO_INSTALL}"; then
            # Set default Iptables-based firewall configutor engine.
            SELECTED_FW=${FW_ENGINE:-"ufw"}
        else
            # Menu Install FW
            echo ""
            echo "Which Firewall configurator engine to install?"
            echo "Available configurator engine:"
            echo "  1). Uncomplicated Firewall (ufw)"
            echo "  2). ConfigServer Security Firewall (csf)"
            echo "  3). Advanced Policy Firewall (apf)"
            echo "------------------------------------------------"

            while [[ ${SELECTED_FW} != "1" && ${SELECTED_FW} != "2" \
                    && ${SELECTED_FW} != "3" && ${SELECTED_FW} != "ufw" \
                    && ${SELECTED_FW} != "csf" && ${SELECTED_FW} != "apf" ]]; do
                read -rp "Select an option [1-3]: " -i "${FW_ENGINE}" -e SELECTED_FW
            done
        fi

        # Ensure that iptables installed.
        if [[ -z $(command -v iptables) ]]; then
            echo "Iptables is required, trying to install it first..."
            run apt-get install -y iptables bash sh
        fi

        case "${SELECTED_FW}" in
            apf)
                install_apf "${SSH_PORT}"
            ;;

            csf)
                install_csf "${SSH_PORT}"
            ;;

            ufw|*)
                install_ufw "${SSH_PORT}"
            ;;
        esac
    else
        warning "Firewall installation skipped..."
    fi
}

function init_secure_server() {
    while [[ "${SECURED_SERVER}" != "y" && "${SECURED_SERVER}" != "n" && "${AUTO_INSTALL}" != true ]]; do
        read -rp "Do you want to enable basic server security? [y/n]: " -i y -e SECURED_SERVER
    done
    if [[ "${SECURED_SERVER}" == Y* || "${SECURED_SERVER}" == y* || "${AUTO_INSTALL}" == true ]]; then
        securing_ssh "$@"
    fi

    install_firewall "$@"

    if [[ ${SSH_PORT} -ne 22 ]]; then
        warning -e "\nYou're running SSH server with modified config, restart to apply your changes."
        echo "  use this command:  service ssh restart"
    fi
}

echo "[Welcome to LEMPer Basic Server Security]"
echo ""

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_secure_server "$@"
