#!/usr/bin/env bash

# Install CrowdSec HIPS
# Min. Requirement  : GNU/Linux Ubuntu/Debian
# Since Version     : 3.3.0

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/utils.sh"

    # Make sure only root can run this installer script.
    requires_root "$@"

    # Make sure only supported distribution can run this installer script.
    preflight_system_check
fi

##
# Install CrowdSec.
##
function init_crowdsec_install() {
    local SELECTED_INSTALLER=""

    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_CROWDSEC}" == true ]]; then
            DO_INSTALL_CROWDSEC="y"
            SELECTED_INSTALLER=${CROWDSEC_INSTALLER:-"repo"}
        else
            DO_INSTALL_CROWDSEC="n"
        fi
    else
        while [[ "${DO_INSTALL_CROWDSEC}" != "y" && "${DO_INSTALL_CROWDSEC}" != "Y" && \
            "${DO_INSTALL_CROWDSEC}" != "n" && "${DO_INSTALL_CROWDSEC}" != "N" ]]; do
            read -rp "Do you want to install CrowdSec HIPS (Host Intrusion Prevention System)? [y/n]: " -e DO_INSTALL_CROWDSEC
        done
    fi

    if [[ ${DO_INSTALL_CROWDSEC} == y* || ${DO_INSTALL_CROWDSEC} == Y* ]]; then
        echo "Available CrowdSec installation method:"
        echo "  1). Install from Repository (repo)"
        echo "  2). Compile from Source (source)"
        echo "-------------------------------------"

        while [[ "${SELECTED_INSTALLER}" != "1" && "${SELECTED_INSTALLER}" != "2" && \
            "${SELECTED_INSTALLER}" != "repo" && "${SELECTED_INSTALLER}" != "source" ]]; do
            read -rp "Select an option [1-2]: " -i "${CROWDSEC_INSTALLER}" -e SELECTED_INSTALLER
        done

        case "${SELECTED_INSTALLER}" in
            1 | "repo")
                echo "Installing CrowdSec from repository..."

                # Add CrowdSec apt repository.
                run curl -sSL https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | bash

                # Install CrowdSec.
                run apt-get install -q -y crowdsec
            ;;
            2 | "source")
                echo "Installing CrowdSec from source..."

                CROWDSEC_VERSION=${CROWDSEC_VERSION:-"1.6.10"}

                if [[ "${CROWDSEC_VERSION}" == "latest" ]]; then
                    CROWDSEC_VERSION=$(curl -sSL https://api.github.com/repos/crowdsecurity/crowdsec/releases/latest | grep -E '^  "tag_name":' | cut -d'"' -f4 | sed 's/^v//')
                fi

                local CURRENT_DIR && \
                CURRENT_DIR=$(pwd)
                run cd "${BUILD_DIR}" || return 1

                # Install from source.
                # https://github.com/crowdsecurity/crowdsec
                local crowdsec_download_link="https://github.com/crowdsecurity/crowdsec/releases/download/v${CROWDSEC_VERSION}/crowdsec_${CROWDSEC_VERSION}_linux_amd64.tar.gz"

                if curl -sLI "${crowdsec_download_link}" | grep -q "HTTP/[.12]* [2].."; then
                    run curl -sSL -o crowdsec.tar.gz "${crowdsec_download_link}" && \
                    run tar -zxf crowdsec.tar.gz && \
                    run cd crowdsec-*/ || return

                    # Build from source.
                    run apt-get install -q -y golang-go libsqlite3-dev
                    run make release
                    run ./crowdsec install --exclude ./cmd/crowdsec-cli
                    run ln -sf "${BUILD_DIR}/crowdsec-*/bin/crowdsec" /usr/local/bin/crowdsec
                    run ln -sf "${BUILD_DIR}/crowdsec-*/bin/crowdsec-cli" /usr/local/bin/crowdsec-cli
                    run ln -sf "${BUILD_DIR}/crowdsec-*/bin/cscli" /usr/local/bin/cscli
                    run cp configs/crowdsec.service /etc/systemd/system/crowdsec.service
                    run systemctl daemon-reload
                fi

                run cd "${CURRENT_DIR}" || return 1
            ;;
        esac

        # Configure CrowdSec.
        echo "Configuring CrowdSec HIPS..."

        if [[ "${DRYRUN}" != true ]]; then
            # Install CrowdSec bouncers (nginx + firewall).
            run apt-get install -q -y crowdsec-bouncer crowdsec-bouncer-nginx

            # Configure CrowdSec collections.
            # https://crowdsecurity.net/
            echo "Installing CrowdSec security collections..."

            # Install SSH brute-force detection.
            run cscli hub update
            run cscli hub install crowdsecurity/ssh-buster
            run cscli hub install crowdsecurity/nginx
            run cscli hub install crowdsecurity/whitelist

            # Enable nginx bouncer in nginx config.
            if [[ -f /etc/nginx/nginx.conf ]]; then
                # Add CrowdSec bouncer include to nginx http block.
                if ! grep -q 'crowdsec-bouncer' /etc/nginx/nginx.conf; then
                    run sed -i '/http {/a \    include /etc/crowdsec/crowdsec-nginx.conf;' /etc/nginx/nginx.conf
                fi
            fi

            # Restart nginx to apply CrowdSec bouncer.
            if [[ -f /lib/systemd/system/nginx.service ]]; then
                run systemctl restart nginx
            fi

            # Enable and start CrowdSec daemon.
            echo "Starting CrowdSec daemon..."
            run systemctl enable crowdsec
            run systemctl restart crowdsec

            if [[ $(pgrep -c crowdsec) -gt 0 ]]; then
                success "CrowdSec HIPS server started successfully."
                info "CrowdSec is now actively monitoring your server."
                echo "    Manage with: cscli"
                echo "    Dashboard:   crowdsec-cli"
            else
                info "Something went wrong with CrowdSec installation."
            fi
        else
            info "CrowdSec installed in dry run mode."
        fi
    else
        info "CrowdSec installation skipped."
    fi
}

echo "[CrowdSec Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v crowdsec) && "${FORCE_INSTALL}" != true ]]; then
    info "CrowdSec already exists, installation skipped."
else
    init_crowdsec_install "$@"
fi
