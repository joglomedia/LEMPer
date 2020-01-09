#!/usr/bin/env bash

# Install Fail2ban
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 25/12/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.3.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellchechk source=scripts/helper.sh
    # shellcheck disable=SC1090
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
        if [[ -n "${FAIL2BAN_INSTALLER}" || "${FAIL2BAN_INSTALLER}" != "none" ]]; then
            DO_INSTALL_FAIL2BAN="n"
        else
            DO_INSTALL_FAIL2BAN="y"
            SELECTED_INSTALLER=${FAIL2BAN_INSTALLER:-"repo"}
        fi
    else
        while [[ "${DO_INSTALL_FAIL2BAN}" != "y" && "${DO_INSTALL_FAIL2BAN}" != "n" ]]; do
            read -rp "Do you want to install Fail2ban server? [y/n]: " -i y -e DO_INSTALL_FAIL2BAN
        done
    fi

    if [[ ${DO_INSTALL_FAIL2BAN} == y* && ${INSTALL_FAIL2BAN} == true ]]; then
        # Install menu.
        echo "Available Fail2ban installation method:"
        echo "  1). Install from Repository (repo)"
        echo "  2). Compile from Source (source)"
        echo "-------------------------------------"

        while [[ ${SELECTED_INSTALLER} != "1" && ${SELECTED_INSTALLER} != "2" && ${SELECTED_INSTALLER} != "none" && \
            ${SELECTED_INSTALLER} != "repo" && ${SELECTED_INSTALLER} != "source" ]]; do
            read -rp "Select an option [1-2]: " -e SELECTED_INSTALLER
        done

        case "${SELECTED_INSTALLER}" in
            1|"repo")
                echo "Installing Fail2ban from repository..."

                if hash apt 2>/dev/null; then
                    run apt install -qq -y fail2ban sendmail
                else
                    fail "Unable to install Fail2ban, this GNU/Linux distribution is not supported."
                fi
            ;;
            2|"source")

                local CURRENT_DIR && \
                CURRENT_DIR=$(pwd)
                run cd "${BUILD_DIR}"

                # Install from source
                # https://github.com/fail2ban/fail2ban
                fail2ban_download_link="https://github.com/fail2ban/fail2ban/archive/${FAIL2BAN_VERSION}.tar.gz"

                if curl -sL --head "${fail2ban_download_link}" | grep -q "HTTP/[.12]* [2].."; then
                    run wget -O fail2ban.tar.gz "${fail2ban_download_link}" && \
                    run tar -zxf fail2ban.tar.gz && \
                    run cd fail2ban-*/ && \
                    run python setup.py install && \
                    run cp files/debian-initd /etc/init.d/fail2ban && \
                    run update-rc.d fail2ban defaults
                fi

                run cd "${CURRENT_DIR}"
            ;;
        esac
    fi

    if "${DRYRUN}"; then
        info "Fail2ban installed in dryrun mode."
    else
        SSH_PORT=${SSH_PORT:-22}

        # Enable jail
        cat > /etc/fail2ban/jail.local <<_EOL_
[DEFAULT]
# banned for 30 days
bantime = 2592000

[sshd]
enabled = true
port = ssh,${SSH_PORT}
filter = sshd
#logpath = /var/log/auth.log
maxretry = 5

[nginx-http-auth]
enabled = true
port    = http,https,8082,8083
maxretry = 5

[postfix]
enabled = true
logpath = /var/log/mail.log
maxretry = 5

[postfix-sasl]
enabled = true
port     = smtp,465,587,submission,imap,imaps,pop3,pop3s
logpath = /var/log/mail.log
maxretry = 5
_EOL_
    fi

    run systemctl start fail2ban
}

echo "[Fail2ban Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v fail2ban-server) ]]; then
    info "Fail2ban already exists. Installation skipped..."
else
    init_fail2ban_install "$@"
fi
