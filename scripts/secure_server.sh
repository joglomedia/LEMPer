#!/usr/bin/env bash

# Basic Server Security Hardening
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 01/07/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    . scripts/helper.sh
fi

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    error "You need to be root to run this script"
    exit 1
fi

echo ""
echo "Welcome to LEMPer Basic Server Security Settings"
echo ""
echo ""

# Securing SSH server.
function securing_ssh() {
    PASSWORDLESS=${PASSWORDLESS:-true}

    if "${PASSWORDLESS}"; then
        echo "Before starting, let's create a pair of keys that some hosts ask for during installation of the server.

On your local machine, open new terminal and create an SSH key pair using the ssh-keygen tool,
use the following command:

ssh-keygen -t rsa -b 4096

After this step, you will have the following files: id_rsa and id_rsa.pub (private and public keys).
Never share your private key.
"

        read -t 60 -p "Press [Enter] to continue..." </dev/tty
        echo ""

        RSA_PUB_KEY=${RSA_PUB_KEY:-n}
        while ! [[ ${RSA_PUB_KEY} =~ ssh-rsa* ]]; do
            #echo -n "Open your public key (id_rsa.pub) file, copy paste the key here: "
            #read RSA_PUB_KEY
            echo "Open your public key (id_rsa.pub) file,"
            read -p "copy paste the key here: " -e RSA_PUB_KEY
        done

        # Grand default account access to SSH with key.
        if [[ ${RSA_PUB_KEY} =~ ssh-rsa* ]]; then
            echo -e "\nSecuring your SSH server with public key..."

            if [ -d /home/lemper/.ssh ]; then
                run mkdir /home/lemper/.ssh
            fi

            # Create authorized_keys file and copy your public key here.
            if "${DRYRUN}"; then
                echo "Add RSA public key for default account in dryrun mode."
            else
                cat > /home/lemper/.ssh/authorized_keys <<EOL
${RSA_PUB_KEY}
EOL

                # Fix ownership and permission.
                chown lemper /home/lemper/.ssh
                chown lemper /home/lemper/.ssh/authorized_keys
                chmod 700 /home/lemper/.ssh
                chmod 600 /home/lemper/.ssh/authorized_keys
                status "RSA public key for default account has been added to the authorized_keys."
            fi

            run sed -i "|^#PermitRootLogin|a PermitRootLogin\ no" /etc/ssh/sshd_config
            run sed -i "|^#PasswordAuthentication yes|a PasswordAuthentication\ no" /etc/ssh/sshd_config
            run sed -i "|^#ClientAliveInterval 0|a ClientAliveInterval\ 600" /etc/ssh/sshd_config
            run sed -i "|^#ClientAliveCountMax|a ClientAliveCountMax\ 3" /etc/ssh/sshd_config
        fi
    fi

    # Securing the SSH server.
    echo ""
    SSH_PORT=${SSH_PORT:-n}
    while ! [[ ${SSH_PORT} =~ ^[0-9]+$ ]]; do
        read -p "SSH Port (LEMPer default SSH port sets to 2269): " -i 2269 -e SSH_PORT
    done

    if [[ ${SSH_PORT} =~ ^[0-9]+$ ]]; then
        echo "Updating SSH port to ${SSH_PORT}..."

        if grep -qwE "Port\ 22" /etc/ssh/sshd_config; then
            run sed -i "|^Port\ 22|#Port\ 22|g" /etc/ssh/sshd_config
            run sed -i "|^#Port\ 22|a Port\ ${SSH_PORT}" /etc/ssh/sshd_config

            status "SSH port updated."
        else
            warning "Unable to update SSH port."
        fi
    fi

    # Restart SSH service after LEMPer installation.
    #run service sshd restart
}

# Install & Configure the Uncomplicated Firewall (UFW)
function install_ufw() {
    SSH_PORT=${@:-$SSH_PORT}

    echo -e "\nInstalling Uncomplicated Firewall (UFW)..."

    if [[ -n $(which ufw) || -n $(which apf) ]]; then
        warning "You should not run any other iptables firewall configuration script.
Any other iptables based firewall will be removed otherwise they will conflict."

        sleep 1

        # Remove CSF+LFD if exists.
        remove_csf

        # Remove APF+BFD if exists.
        remove_apf
    fi

    # Install UFW
    run apt-get install -y ufw

    if [[ -n $(which ufw) ]]; then
        echo "Configuring firewall rules..."

        # Close all incoming ports.
        run ufw default deny incoming

        # Open all outgoing ports.
        run ufw default allow outgoing

        # Open SSH port.
        run ufw allow ${SSH_PORT}/tcp

        # Open HTTP port.
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

        # Open ntp port : to sync the clock of your machine.
        run ufw allow 123/udp

        # Turn on firewall.
        run ufw enable
    fi
}

# Install & Configure the ConfigServer Security & Firewall (CSF)
function install_csf() {
    SSH_PORT=${@:-$SSH_PORT}

    echo -e "\nInstalling CSF+LFD firewall..."

    if [[ -n $(which ufw) || -n $(which apf) ]]; then
        warning "You should not run any other iptables firewall configuration script.
Any other iptables based firewall will be removed otherwise they will conflict."

        sleep 1

        # Remove default Ubuntu firewall (UFW) if exists.
        remove_ufw

        # Remove APF+BFD if exists.
        remove_apf
    fi

    # Install requirements.
    echo -e "\nInstalling requirement packages..."

    if [[ -n $(which cpan) ]]; then
        run cpan -i "LWP LWP::Protocol::https GD::Graph IO::Socket::INET6"
    else
        run apt-get -y install libwww-perl liblwp-protocol-https-perl libgd-graph-perl
    fi

    echo -e "\nInstalling CSF+LFD firewall..."
    run wget -q https://download.configserver.com/csf.tgz
    run tar -xzf csf.tgz
    run cd csf/

    if [ -f install.sh ]; then
        run sh install.sh
    fi

    run cd ../

    echo "Verifying required iptables modules..."
    if "${DRYRUN}"; then
        status "Installation verified in dryrun mode."
    else
        run perl /usr/local/csf/bin/csftest.pl

        echo ""
        if [ -f /etc/csf/csf.conf ]; then
            echo "Configuring CSF+LFD firewall..."

            run sed -i 's|^TESTING\ =\ "1"|TESTING\ =\ "0"|g' /etc/csf/csf.conf
            run sed -i 's|^TCP_IN|#TCP_IN|g' /etc/csf/csf.conf
            run sed -i "s|^#TCP_IN|a TCP_IN = /
                \"20,21,25,53,80,110,143,443,465,587,993,995,8081,8082,8083,${SSH_PORT}\""
            run sed -i 's|^TCP_OUT|#TCP_OUT|g' /etc/csf/csf.conf
            run sed -i "s|^#TCP_OUT|a TCP_OUT = /
                \"20,21,25,53,80,110,143,443,465,587,993,995,8081,8082,8083,${SSH_PORT}\""

            # IPv6 (Ip6tables)
            ip6tables_version=$(ip6tables --version | grep 'v' | cut -d'v' -f2)
            if version_older_than "$ip6tables_version" "1.4.3"; then
                echo "Configuring CSF+LFD for IPv6..."

                run sed -i 's|^IPV6\ =\ "0"|IPV6\ =\ "1"|g' /etc/csf/csf.conf
                run sed -i 's|^TCP6_IN|#TCP6_IN|g' /etc/csf/csf.conf
                run sed -i "s|^#TCP6_IN|a TCP6_IN = /
                    \"20,21,25,53,80,110,143,443,465,587,993,995,8081,8082,8083,${SSH_PORT}\""
                run sed -i 's|^TCP6_OUT|#TCP6_OUT|g' /etc/csf/csf.conf
                run sed -i "s|^#TCP6_OUT|a TCP6_OUT = /
                    \"20,21,25,53,80,110,143,443,465,587,993,995,8081,8082,8083,${SSH_PORT}\""
            fi

            if [[ -n $(which csf) && -n $(which lfd) ]]; then
                status "CSF+LFD firewall installed. Starting now..."
                run service csf restart
                run service lfd restart
            fi
        fi
    fi

    # Clean up installation files.
    run rm -fr csf/
}

# Install & Configure the Advancef Policy Firewall (APF)
function install_apf() {
    SSH_PORT=${@:-$SSH_PORT}

    echo -e "\nInstalling APF+BFD iptables firewall..."

    if [[ -n $(which ufw) || -n $(which csf) ]]; then
        warning "You should not run any other iptables firewall configuration script.
Any other iptables based firewall will be removed otherwise they will conflict."

        sleep 1

        # Remove default Ubuntu firewall (UFW) if exists.
        remove_ufw

        # Remove CSF+LFD if exists.
        remove_csf
    fi

    # Get ethernet interface.
    IFACE=$(ls /sys/class/net | grep ^enp)

    run wget -q --no-check-certificate https://github.com/rfxn/advanced-policy-firewall/archive/1.7.6-1.tar.gz \
        -O apf.tar.gz
    run tar -xf apf.tar.gz
    run cd advanced-policy-firewall-*/

    if [ -f install.sh ]; then
        run sh install.sh
    fi

    run cd ../



}

function remove_ufw() {
    if [[ -n $(which ufw) ]]; then
        echo "Found UFW iptables firewall, trying to remove it..."

        run service ufw stop
        run ufw disable

        echo "Removing UFW iptables firewall..."

        run apt-get -y remove ufw
    fi
}

function remove_csf() {
    if [[ -n $(which csf) || -f /usr/lib/systemd/system/csf.service ]]; then
        echo "Found CSF+LFD iptables firewall, trying to remove it..."

        if [[ -f /etc/csf/uninstall.sh ]]; then
            run sh /etc/csf/uninstall.sh
        fi
    fi
}

function remove_apf() {
    if [[ -n $(which apf) && -f /etc/apf/conf.apf ]]; then
        echo "Found APF+BFD iptables firewall, trying to remove it..."

        run service apf stop

        echo "Removing APF+BFD iptables firewall..."

        #run service iptables stop
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
    INSTALL_FW=${INSTALL_FW:-n}
    while [[ ${INSTALL_FW} != "y" && ${INSTALL_FW} != "n" && ${INSTALL_FW} != true ]]; do
        read -p "Do you want to install Firewall? [y/n]: " -i y -e INSTALL_FW
    done

    if [[ "${INSTALL_FW}" == true || "${INSTALL_FW}" == Y* || "${INSTALL_FW}" == y* ]]; then

        if "${AUTO_INSTALL}"; then
            # Set default Iptables-based firewall configutor engine.
            SELECTED_FW=${FW_ENGINE:-"ufw"}
        else
            # Menu Install FW
            echo ""
            echo "Welcome to Iptables Firewall Configurator Installer"
            echo ""
            echo "Which Firewall configurator engine to install?"
            echo "Available Firewall engine:"
            echo "  1). Uncomplicated Firewall (ufw)"
            echo "  2). ConfigServer Security Firewall (csf)"
            echo "  3). Advanced Policy Firewall (apf)"
            echo "------------------------------------------------"

            while [[ $SELECTED_FW != "1" && $SELECTED_FW != "2" \
                    && $SELECTED_FW != "3" && $SELECTED_FW != "ufw" \
                    && $SELECTED_FW != "csf" && $SELECTED_FW != "apf" ]]; do
                read -p "Select an option [1-3]: " -i ${FW_ENGINE} -e SELECTED_FW
            done
        fi

        # Ensure that iptables installed.
        if [[ -z $(which iptables) ]]; then
            echo "Iptables is required, trying to install it first..."
            run apt-get install -y iptables
        fi

        case ${SELECTED_FW} in
            apf)
                install_apf ${SSH_PORT}
            ;;

            csf)
                install_csf ${SSH_PORT}
            ;;

            ufw|*)
                install_ufw ${SSH_PORT}
            ;;
        esac
    fi
}

### Main
securing_ssh
install_firewall

# Configure server clock.
echo -e "\nReconfigure server clock..."
run dpkg-reconfigure tzdata
