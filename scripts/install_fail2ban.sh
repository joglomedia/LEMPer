#!/usr/bin/env bash

# Install Fail2ban
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 11/12/2021
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.3.0

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

##
# Install Fail2ban.
##
function init_fail2ban_install() {
    local SELECTED_INSTALLER=""

    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_FAIL2BAN}" == true ]]; then
            DO_INSTALL_FAIL2BAN="y"
            SELECTED_INSTALLER=${FAIL2BAN_INSTALLER:-"repo"}
        else
            DO_INSTALL_FAIL2BAN="n"
        fi
    else
        while [[ "${DO_INSTALL_FAIL2BAN}" != "y" && "${DO_INSTALL_FAIL2BAN}" != "Y" && \
            "${DO_INSTALL_FAIL2BAN}" != "n" && "${DO_INSTALL_FAIL2BAN}" != "N" ]]; do
            read -rp "Do you want to install fail2ban server? [y/n]: " -e DO_INSTALL_FAIL2BAN
        done
    fi

    if [[ ${DO_INSTALL_FAIL2BAN} == y* || ${DO_INSTALL_FAIL2BAN} == Y* ]]; then
        echo "Available Fail2ban installation method:"
        echo "  1). Install from Repository (repo)"
        echo "  2). Compile from Source (source)"
        echo "-------------------------------------"

        while [[ "${SELECTED_INSTALLER}" != "1" && "${SELECTED_INSTALLER}" != "2" && \
            "${SELECTED_INSTALLER}" != "repo" && "${SELECTED_INSTALLER}" != "source" ]]; do
            read -rp "Select an option [1-2]: " -i "${FAIL2BAN_INSTALLER}" -e SELECTED_INSTALLER
        done

        case "${SELECTED_INSTALLER}" in
            1 | "repo")
                echo "Installing Fail2ban from repository..."
                run apt-get install -qq -y fail2ban
            ;;
            2 | "source")
                echo "Installing Fail2ban from source..."

                FAIL2BAN_VERSION=${FAIL2BAN_VERSION:-"0.11.2"}
                local CURRENT_DIR && \
                CURRENT_DIR=$(pwd)
                run cd "${BUILD_DIR}" || return 1

                # Install from source
                # https://github.com/fail2ban/fail2ban
                fail2ban_download_link="https://github.com/fail2ban/fail2ban/archive/${FAIL2BAN_VERSION}.tar.gz"

                if curl -sLI "${fail2ban_download_link}" | grep -q "HTTP/[.12]* [2].."; then
                    run wget "${fail2ban_download_link}" -O fail2ban.tar.gz -q --show-progress && \
                    run tar -zxf fail2ban.tar.gz && \
                    run cd fail2ban-*/ && \
                    run python setup.py install && \
                    run cp files/debian-initd /etc/init.d/fail2ban && \
                    run update-rc.d fail2ban defaults
                fi

                run cd "${CURRENT_DIR}" || return 1
            ;;
        esac

        # Configure Fal2ban.
        echo "Configuring Fail2ban..."

        if [[ "${DRYRUN}" != true ]]; then
            SSH_PORT=${SSH_PORT:-22}

            # Add Wordpress custom filter.
            run cp -f etc/fail2ban/filter.d/wordpress.conf /etc/fail2ban/filter.d/

            # Enable jail
            cat > /etc/fail2ban/jail.local <<EOL
[DEFAULT]
# banned for 30 days
bantime = 30d

# ignored ip (googlebot) - https://ipinfo.io/AS15169
ignoreip = 66.249.64.0/19 66.249.64.0/20 66.249.80.0/22 66.249.84.0/23 66.249.88.0/24

[sshd]
enabled = true
port = ssh,${SSH_PORT}
filter = sshd
logpath = /var/log/auth.log
maxretry = 3

[nginx-http-auth]
enabled = true
port = http,https,8082,8083
maxretry = 3

EOL

            # Enable jail for Postfix & Dovecot
            if [[ "${INSTALL_MAILER}" == true ]]; then
                cat >> /etc/fail2ban/jail.local <<EOL
[postfix]
enabled = true
logpath = /var/log/mail.log
maxretry = 3

[postfix-sasl]
enabled = true
port = smtp,465,587,submission,imap,imaps,pop3,pop3s
logpath = /var/log/mail.log
maxretry = 3

EOL
            fi
        fi

        # Restart Fail2ban daemon.
        echo "Starting Fail2ban server..."
        run systemctl start fail2ban

        if [[ "${DRYRUN}" != true ]]; then
            if [[ $(pgrep -c fail2ban-server) -gt 0 ]]; then
                success "Fail2ban server started successfully."
            else
                info "Something went wrong with Fail2ban installation."
            fi
        else
            info "Fail2ban installed in dry run mode."
        fi
    else
        info "Fail2ban installation skipped."
    fi
}

echo "[Fail2ban Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v fail2ban-server) ]]; then
    info "Fail2ban already exists, installation skipped."
else
    if [[ "${INSTALL_FAIL2BAN}" == true ]]; then
        init_fail2ban_install "$@"
    else
        info "Fail2ban installation skipped."
    fi
fi
