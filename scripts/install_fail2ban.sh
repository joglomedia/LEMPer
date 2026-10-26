#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | Fail2ban Installer                                                      |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2026 MasEDI.Net (https://masedi.net/lemper)          |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@lemper.cloud so we can send you a copy immediately.          |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <me@masedi.net>                                |
# +-------------------------------------------------------------------------+

if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )
    cd "${BASE_DIR}" || { echo "Cannot enter ${BASE_DIR}."; exit 1; }
    # shellcheck source=scripts/utils.sh
    . "${BASE_DIR}/scripts/utils.sh"

    # Make sure only root can run this installer script.
    requires_root "$@"

    # Make sure only supported distribution can run this installer script.
    preflight_system_check
fi

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
                # The Ubuntu/Debian package byte-compiles its own test files,
                # which emit SyntaxWarning (invalid escape sequence) noise on
                # newer Python. Suppress only that category during install.
                run env PYTHONWARNINGS=ignore::SyntaxWarning apt-get install -q -y fail2ban
            ;;
            2 | "source")
                echo "Installing Fail2ban from source..."

                FAIL2BAN_VERSION=${FAIL2BAN_VERSION:-"1.1.0"}

                if [[ "${FAIL2BAN_VERSION}" == "latest" ]]; then
                    FAIL2BAN_VERSION="master"
                fi

                local CURRENT_DIR && \
                CURRENT_DIR=$(pwd)
                run mkdir -p "${BUILD_DIR}"
                if [[ "${DRYRUN}" == true ]]; then
                    info "would enter ${BUILD_DIR}"
                else
                    cd "${BUILD_DIR}" || exit 1
                fi

                # Install from source
                # https://github.com/fail2ban/fail2ban
                fail2ban_download_link="https://github.com/fail2ban/fail2ban/archive/${FAIL2BAN_VERSION}.tar.gz"

                if curl -sLI "${fail2ban_download_link}" | grep -q "HTTP/[.12]* [2].."; then
                    run curl -sSL -o fail2ban.tar.gz "${fail2ban_download_link}" && \
                    run tar -zxf fail2ban.tar.gz
                    if [[ "${DRYRUN}" == true ]]; then
                        info "would enter fail2ban-${FAIL2BAN_VERSION}"
                    else
                        cd fail2ban-*/ || exit 1
                    fi

                    # Convert to Python3 codebase
                    run python -m venv /opt/fail2ban/ && \
                    run /opt/fail2ban/bin/pip install --upgrade pip setuptools cffi 2to3 && \
                    run ln -sf /opt/fail2ban/bin/2to3 /usr/local/bin/2to3 && \
                    run ./fail2ban-2to3 && \
                    run /opt/fail2ban/bin/python setup.py install && \
                    run ln -sf /opt/fail2ban/bin/fail2ban-client /usr/bin/fail2ban-client && \
                    run ln -sf /opt/fail2ban/bin/fail2ban-server /usr/bin/fail2ban-server && \
                    run ln -sf /opt/fail2ban/bin/fail2ban-regex /usr/bin/fail2ban-regex && \
                    run ln -sf /opt/fail2ban/bin/fail2ban-testcases /usr/bin/fail2ban-testcases && \
                    run ln -sf /opt/fail2ban/bin/python /usr/bin/fail2ban-python

                    if [[ -f files/debian-initd ]]; then
                        run cp files/debian-initd /etc/init.d/fail2ban
                        run update-rc.d fail2ban defaults
                    fi
                fi

                if [[ "${DRYRUN}" == true ]]; then
                    info "would return to ${CURRENT_DIR}"
                else
                    cd "${CURRENT_DIR}" || exit 1
                fi
            ;;
        esac

        # Configure Fail2ban.
        echo "Configuring Fail2ban..."

        if [[ "${DRYRUN}" != true ]]; then
            SSH_PORT=${SSH_PORT:-22}

            # Add custom filter.
            run cp -fr etc/fail2ban/filter.d/*.conf /etc/fail2ban/filter.d/

            # Enable jail.
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
filter = nginx-http-auth
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

        # Install a systemd unit when the source build did not provide one.
        FAIL2BAN_UNIT="/lib/systemd/system/fail2ban.service"
        if [[ ! -f "${FAIL2BAN_UNIT}" && ! -f /etc/systemd/system/fail2ban.service ]]; then
            if [[ -f etc/systemd/fail2ban.service ]]; then
                run cp etc/systemd/fail2ban.service "${FAIL2BAN_UNIT}"
            else
                warning "No Fail2ban systemd unit found; the service must be started manually."
            fi
        fi

        # Restart Fail2ban daemon.
        if [[ -f "${FAIL2BAN_UNIT}" || -f /etc/systemd/system/fail2ban.service ]] && \
            command -v systemctl >/dev/null 2>&1; then
            echo "Starting Fail2ban server..."
            run systemctl daemon-reload
            run systemctl enable fail2ban
            run systemctl restart fail2ban
        fi

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
if [[ -n $(command -v fail2ban-server) && "${FORCE_INSTALL}" != true ]]; then
    info "Fail2ban already exists, installation skipped."
else
    init_fail2ban_install "$@"
fi
