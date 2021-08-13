#!/usr/bin/env bash

# Install Fail2ban
# Min. Requirement  : GNU/Linux Ubuntu 16.04
# Last Build        : 05/06/2021
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.3.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASEDIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

##
# Install Fail2ban.
#
function init_fail2ban_install() {
    local SELECTED_INSTALLER=""

    if "${AUTO_INSTALL}"; then
        DO_INSTALL_FAIL2BAN="y"
        SELECTED_INSTALLER=${FAIL2BAN_INSTALLER:-"repo"}
    else
        while [[ "${DO_INSTALL_FAIL2BAN}" != "y" && "${DO_INSTALL_FAIL2BAN}" != "Y" && \
            "${DO_INSTALL_FAIL2BAN}" != "n" && "${DO_INSTALL_FAIL2BAN}" != "N" ]]; do
            read -rp "Do you want to install fail2ban server? [y/n]: " -e DO_INSTALL_FAIL2BAN
        done
    fi

    if [[ ${DO_INSTALL_FAIL2BAN} == y* || ${DO_INSTALL_FAIL2BAN} == Y* ]]; then
        # Install menu.
        echo "Available Fail2ban installation method:"
        echo "  1). Install from Repository (repo)"
        echo "  2). Compile from Source (source)"
        echo "-------------------------------------"

        while [[ "${SELECTED_INSTALLER}" != "1" && "${SELECTED_INSTALLER}" != "2" && \
            "${SELECTED_INSTALLER}" != "repo" && "${SELECTED_INSTALLER}" != "source" ]]; do
            read -rp "Select an option [1-2]: " -i "${FAIL2BAN_INSTALLER}" -e SELECTED_INSTALLER
        done

        case "${SELECTED_INSTALLER}" in
            1|"repo")
                echo "Installing Fail2ban from repository..."

                if hash apt-get 2>/dev/null; then
                    run apt-get install -qq -y fail2ban sendmail
                else
                    fail "Unable to install Fail2ban, this GNU/Linux distribution is not supported."
                fi
            ;;
            2|"source")
                FAIL2BAN_VERSION=${FAIL2BAN_VERSION:-"0.10.5"}
                local CURRENT_DIR && \
                CURRENT_DIR=$(pwd)
                run cd "${BUILD_DIR}" || return 1

                # Install from source
                # https://github.com/fail2ban/fail2ban
                fail2ban_download_link="https://github.com/fail2ban/fail2ban/archive/${FAIL2BAN_VERSION}.tar.gz"

                if curl -sLI "${fail2ban_download_link}" | grep -q "HTTP/[.12]* [2].."; then
                    run wget -O fail2ban.tar.gz "${fail2ban_download_link}" && \
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
        if "${DRYRUN}"; then
            info "Configuring Fail2ban in dryrun mode."
        else
            SSH_PORT=${SSH_PORT:-22}

            # Add Wordpress custom filter.
            run cp -f etc/fail2ban/filter.d/wordpress.conf /etc/fail2ban/filter.d/

            # Enable jail
            cat > /etc/fail2ban/jail.local <<_EOL_
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
port    = http,https,8082,8083
maxretry = 3

_EOL_
        fi

        # Enable jail for Postfix & Dovecot
        if "${INSTALL_MAILER}"; then
            cat >> /etc/fail2ban/jail.local <<_EOL_
[postfix]
enabled = true
logpath = /var/log/mail.log
maxretry = 3

[postfix-sasl]
enabled = true
port     = smtp,465,587,submission,imap,imaps,pop3,pop3s
logpath = /var/log/mail.log
maxretry = 3

_EOL_
        fi

        # Restart Redis daemon.
        echo "Starting Fail2ban server..."
        run systemctl start fail2ban

        if "${DRYRUN}"; then
            info "Fail2ban installed in dryrun mode."
        else
            if [[ $(pgrep -c fail2ban-server) -gt 0 ]]; then
                success "Fail2ban server started successfully."
            else
                info "Something went wrong with Fail2ban installation."
            fi
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
    if [[ ${INSTALL_FAIL2BAN} == true ]]; then
        init_fail2ban_install "$@"
    else
        info "Fail2ban installation skipped."
    fi
fi
