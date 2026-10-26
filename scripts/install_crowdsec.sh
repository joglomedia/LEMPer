#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | CrowdSec HIPS Installer                                                 |
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
        # Unattended installs already chose a method. Only prompt when it is missing.
        if [[ "${SELECTED_INSTALLER}" != "1" && "${SELECTED_INSTALLER}" != "2" && \
            "${SELECTED_INSTALLER}" != "repo" && "${SELECTED_INSTALLER}" != "source" ]]; then
            echo "Available CrowdSec installation method:"
            echo "  1). Install from Repository (repo)"
            echo "  2). Compile from Source (source)"
            echo "-------------------------------------"

            while [[ "${SELECTED_INSTALLER}" != "1" && "${SELECTED_INSTALLER}" != "2" && \
                "${SELECTED_INSTALLER}" != "repo" && "${SELECTED_INSTALLER}" != "source" ]]; do
                read -rp "Select an option [1-2]: " -i "${CROWDSEC_INSTALLER}" -e SELECTED_INSTALLER
            done
        fi

        case "${SELECTED_INSTALLER}" in
            1 | "repo")
                echo "Installing CrowdSec from repository..."

                # Add CrowdSec apt repository. Download the setup script first so
                # a failed download is detected instead of being piped to bash.
                local CROWDSEC_REPO_SETUP="${BUILD_DIR}/crowdsec-repo-setup.sh"
                run curl -fsSL -o "${CROWDSEC_REPO_SETUP}" \
                    https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh
                run bash "${CROWDSEC_REPO_SETUP}"

                # Install CrowdSec.
                run apt-get install -q -y crowdsec
            ;;
            2 | "source")
                echo "Installing CrowdSec from source..."
                install_crowdsec_from_source
            ;;
        esac

        # Configure CrowdSec.
        echo "Configuring CrowdSec HIPS..."

        if [[ "${DRYRUN}" != true ]]; then
            # Source installs place cscli in /usr/local/bin. The repository
            # package uses /usr/bin. Either location must be reachable here.
            export PATH="/usr/local/sbin:/usr/local/bin:${PATH}"

            # Register the local machine so cscli can talk to the local API
            # without an interactive login prompt.
            run cscli machines add --force "$(cat /etc/machine-id)" -a \
                -f /etc/crowdsec/local_api_credentials.yaml

            # Configure CrowdSec collections.
            # https://crowdsecurity.net/
            echo "Installing CrowdSec security collections..."
            run cscli hub update
            run cscli hub install crowdsecurity/linux
            run cscli hub install crowdsecurity/sshd
            run cscli hub install crowdsecurity/nginx
            run cscli hub install crowdsecurity/whitelist-good-actors

            # Install PHP web app security collections (WordPress priority).
            install_crowdsec_webapp_support

            # Create the optional per-vhost hardening include.
            configure_crowdsec_webapp_rules

            # Enable and start CrowdSec daemon before installing bouncers so
            # they can register against the local API.
            echo "Starting CrowdSec daemon..."
            run systemctl enable crowdsec
            run systemctl restart crowdsec

            install_crowdsec_bouncers

            # Apply the bouncer to a running nginx, if any.
            if command -v nginx >/dev/null 2>&1; then
                if ! nginx -t; then
                    warning "Nginx configuration test failed after installing CrowdSec."
                fi
                if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nginx; then
                    run systemctl reload nginx
                fi
            fi

            if [[ $(pgrep -x crowdsec | wc -l) -gt 0 ]]; then
                success "CrowdSec HIPS server started successfully."
                info "CrowdSec is now actively monitoring your server."
                echo "    Decisions: cscli decisions list"
                echo "    Metrics:   cscli metrics"
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

##
# Download and install CrowdSec outside the distribution repositories.
# Upstream publishes statically linked amd64 binaries with each release; other
# architectures are compiled from the tagged source tree.
##
function install_crowdsec_from_source() {
    local CROWDSEC_VERSION="${CROWDSEC_VERSION:-"1.6.10"}"
    local CURRENT_DIR
    CURRENT_DIR=$(pwd)

    if [[ "${CROWDSEC_VERSION}" == "latest" ]]; then
        CROWDSEC_VERSION=$(curl -fsSL https://api.github.com/repos/crowdsecurity/crowdsec/releases/latest |
            sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -n 1)

        if [[ -z "${CROWDSEC_VERSION}" ]]; then
            warning "Unable to resolve the latest CrowdSec version, using 1.6.10."
            CROWDSEC_VERSION="1.6.10"
        fi
    fi

    run mkdir -p "${BUILD_DIR}"
    # `run cd` is a no-op in dry-run mode, so change directory directly.
    if [[ "${DRYRUN}" == true ]]; then
        info "would enter ${BUILD_DIR}"
    else
        cd "${BUILD_DIR}" || exit 1
    fi

    if [[ "$(uname -m)" == "x86_64" ]]; then
        local CROWDSEC_RELEASE_ARCHIVE="https://github.com/crowdsecurity/crowdsec/releases/download/v${CROWDSEC_VERSION}/crowdsec-release.tgz"
        run curl -fsSL -o crowdsec-release.tgz "${CROWDSEC_RELEASE_ARCHIVE}"
        run tar -xzf crowdsec-release.tgz
        if [[ "${DRYRUN}" == true ]]; then
            info "would enter crowdsec-v${CROWDSEC_VERSION}"
        else
            cd "crowdsec-v${CROWDSEC_VERSION}" || exit 1
        fi
    else
        # No prebuilt binaries for this architecture: compile from source.
        run apt-get install -q -y build-essential pkg-config libsqlite3-dev
        install_crowdsec_go_toolchain "${CROWDSEC_VERSION}"

        local CROWDSEC_SOURCE_ARCHIVE="https://github.com/crowdsecurity/crowdsec/archive/refs/tags/v${CROWDSEC_VERSION}.tar.gz"
        run curl -fsSL -o crowdsec-src.tar.gz "${CROWDSEC_SOURCE_ARCHIVE}"
        run tar -xzf crowdsec-src.tar.gz
        if [[ "${DRYRUN}" == true ]]; then
            info "would enter crowdsec-${CROWDSEC_VERSION}"
        else
            cd "crowdsec-${CROWDSEC_VERSION}" || exit 1
        fi
        run_spinner "Building CrowdSec" make build BUILD_RE2_WASM=1
    fi

    # The wizard installs the binaries, patterns, configuration, and systemd
    # unit. It is safe to skip when a configuration already exists: in that
    # case only the binaries are refreshed.
    run apt-get install -q -y gettext-base
    if [[ -f /etc/crowdsec/config.yaml ]]; then
        run install -m 755 cmd/crowdsec/crowdsec /usr/local/bin/crowdsec
        run install -m 755 cmd/crowdsec-cli/cscli /usr/local/bin/cscli
    else
        run ./wizard.sh --bininstall --force
    fi
    run systemctl daemon-reload

    if [[ "${DRYRUN}" == true ]]; then
        info "would return to ${CURRENT_DIR}"
    else
        cd "${CURRENT_DIR}" || exit 1
    fi
}

##
# Install a Go toolchain new enough for the CrowdSec source tree.
# The version is read from upstream go.mod so it does not drift.
##
function install_crowdsec_go_toolchain() {
    local CROWDSEC_VERSION="${1}"
    local GO_VERSION
    GO_VERSION=$(curl -fsSL "https://raw.githubusercontent.com/crowdsecurity/crowdsec/v${CROWDSEC_VERSION}/go.mod" |
        sed -n 's/^go //p' | head -n 1)
    GO_VERSION=${GO_VERSION:-"1.24.4"}

    if command -v go >/dev/null 2>&1; then
        local GO_INSTALLED
        GO_INSTALLED=$(go env GOVERSION 2>/dev/null | sed 's/^go//')
        if [[ -n "${GO_INSTALLED}" ]] && \
            [[ "$(printf '%s\n%s\n' "${GO_VERSION}" "${GO_INSTALLED}" | sort -V | head -n 1)" == "${GO_VERSION}" ]]; then
            return 0
        fi
    fi

    local GO_ARCH
    case "$(uname -m)" in
        x86_64) GO_ARCH="amd64" ;;
        aarch64 | arm64) GO_ARCH="arm64" ;;
        armv7l | armv6l) GO_ARCH="armv6l" ;;
        *)
            fail "Unsupported architecture for the Go toolchain: $(uname -m)."
        ;;
    esac

    local GO_ROOT="/opt/go-${GO_VERSION}"
    echo "Installing Go ${GO_VERSION} toolchain..."
    run curl -fsSL -o "${BUILD_DIR}/go.tar.gz" "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
    run mkdir -p "${GO_ROOT}"
    run tar -C "${GO_ROOT}" --strip-components=1 -xzf "${BUILD_DIR}/go.tar.gz"
    export PATH="${GO_ROOT}/bin:${PATH}"
    export GOTOOLCHAIN=local
}

##
# Install CrowdSec bouncers. The firewall bouncer works independently of the
# nginx build; the nginx bouncer is only usable when nginx has the Lua module.
##
function install_crowdsec_bouncers() {
    if apt-cache show crowdsec-firewall-bouncer-iptables >/dev/null 2>&1; then
        run apt-get install -q -y crowdsec-firewall-bouncer-iptables
    else
        warning "CrowdSec firewall bouncer package is not available, skipping."
    fi

    local HAS_NGINX_LUA=false
    if command -v nginx >/dev/null 2>&1 && nginx -V 2>&1 | grep -q 'http_lua_module'; then
        HAS_NGINX_LUA=true
    elif compgen -G "/etc/nginx/modules-enabled/*lua*" >/dev/null; then
        HAS_NGINX_LUA=true
    fi

    if [[ "${HAS_NGINX_LUA}" != true ]]; then
        info "Nginx was built without the Lua module; the nginx bouncer is not installed."
        return 0
    fi

    if apt-cache show crowdsec-nginx-bouncer >/dev/null 2>&1; then
        run apt-get install -q -y crowdsec-nginx-bouncer
    else
        warning "CrowdSec nginx bouncer package is not available, skipping."
    fi
}

##
# Install CrowdSec collections for PHP web applications.
# Priority: WordPress (most common LEMPer use case).
##
function install_crowdsec_webapp_support() {
    local INSTALL_CROWDSEC_WORDPRESS="${INSTALL_CROWDSEC_WORDPRESS:-true}"
    local INSTALL_CROWDSEC_PHPAPPS="${INSTALL_CROWDSEC_PHPAPPS:-false}"

    echo "Installing PHP web application security collections..."

    # Generic HTTP attack scenarios for every web application.
    run cscli hub install crowdsecurity/base-http-scenarios

    # WordPress security (highest priority).
    if [[ "${INSTALL_CROWDSEC_WORDPRESS}" == true ]]; then
        echo "Installing WordPress security scenarios..."
        run cscli hub install crowdsecurity/wordpress
    fi

    # Other popular PHP web apps.
    if [[ "${INSTALL_CROWDSEC_PHPAPPS}" == true ]]; then
        echo "Installing additional PHP web app scenarios..."
        run cscli hub install crowdsecurity/magento
        run cscli hub install crowdsecurity/nextcloud
    fi

    success "PHP web application security collections installed."
}

##
# Create an optional per-vhost nginx include with PHP web app hardening rules.
##
function configure_crowdsec_webapp_rules() {
    local config_dir="/etc/lemper/waf"
    run mkdir -p "${config_dir}"

    cat > "${config_dir}/crowdsec-webapp.conf" <<'EOF'
## Optional PHP web application hardening rules.
# Add inside a server{} block:
#   include /etc/lemper/waf/crowdsec-webapp.conf;
# Keep this after the PHP handler location so these rules do not shadow it.

# Block access to wp-config.php and .htaccess/.user.ini.
location ~* /(?:wp-config\.php|\.htaccess|\.user\.ini)$ {
    return 444;
}

# wp-includes scripts must not be requested directly.
location ~* /wp-includes/.*\.php$ {
    return 444;
}
EOF

    success "CrowdSec PHP web app hardening include created."
    info "Include /etc/lemper/waf/crowdsec-webapp.conf inside a vhost server{} block to enable it."
}

echo "[CrowdSec Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v crowdsec) && "${FORCE_INSTALL}" != true ]]; then
    info "CrowdSec already exists, installation skipped."
else
    init_crowdsec_install "$@"
fi
