#!/usr/bin/env bash

# Bun.js runtime installer
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 12/02/2022
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 2.6.0

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
# Install Bun.js runtime.
# Bun is a fast JavaScript/TypeScript runtime designed as a drop-in
# replacement for Node.js, with built-in npm client, test runner, and bundler.
# https://bun.sh
##
function init_bunjs_install() {
    local SELECTED_INSTALLER=""

    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_BUNJS}" == true ]]; then
            DO_INSTALL_BUNJS="y"
            SELECTED_INSTALLER=${BUNJS_INSTALLER:-"repo"}
        else
            DO_INSTALL_BUNJS="n"
        fi
    else
        while [[ "${DO_INSTALL_BUNJS}" != "y" && "${DO_INSTALL_BUNJS}" != "Y" && \
            "${DO_INSTALL_BUNJS}" != "n" && "${DO_INSTALL_BUNJS}" != "N" ]]; do
            read -rp "Do you want to install Bun.js runtime? [y/n]: " -e DO_INSTALL_BUNJS
        done
    fi

    if [[ ${DO_INSTALL_BUNJS} == y* || ${DO_INSTALL_BUNJS} == Y* ]]; then
        echo "Available Bun.js installation method:"
        echo "  1). Install from Repository (repo) — apt package"
        echo "  2). Compile from Source (source) — official binary release"
        echo "-------------------------------------"

        while [[ "${SELECTED_INSTALLER}" != "1" && "${SELECTED_INSTALLER}" != "2" && \
            "${SELECTED_INSTALLER}" != "repo" && "${SELECTED_INSTALLER}" != "source" ]]; do
            read -rp "Select an option [1-2]: " -i "${BUNJS_INSTALLER:-repo}" -e SELECTED_INSTALLER
        done

        case "${SELECTED_INSTALLER}" in
            1 | "repo")
                echo "Installing Bun.js from apt repository..."

                # Add Bun.js apt repository.
                run bash -c "curl -fsSL https://bun.sh/bun.key | gpg --dearmor --yes -o /usr/share/keyrings/bun-archive-keyring.gpg" && \
                run bash -c "echo 'deb [signed-by=/usr/share/keyrings/bun-archive-keyring.gpg] https://bun.sh/apt stable main' | tee /etc/apt/sources.list.d/bun.list" && \
                run apt-get update --allow-releaseinfo-change -q -y && \
                run apt-get install -q -y bun
            ;;
            2 | "source")
                echo "Installing Bun.js from official binary release..."

                local CURRENT_DIR && \
                CURRENT_DIR=$(pwd)
                run cd "${BUILD_DIR}" || error "Cannot change directory to ${BUILD_DIR}"

                BUNJS_VERSION=${BUNJS_VERSION:-"latest"}

                if [[ "${BUNJS_VERSION}" == "latest" ]]; then
                    BUNJS_API_URL="https://api.github.com/repos/oven-sh/bun-release/latest"
                    BUNJS_DOWNLOAD_URL=$(curl -fsSL "${BUNJS_API_URL}" | grep -o '"browser_download_url": *"[^"]*linux-x64\[^"]*"' | head -1 | cut -d'"' -f4)
                else
                    BUNJS_DOWNLOAD_URL="https://github.com/oven-sh/bun-release/releases/download/${BUNJS_VERSION}/bun-linux-x64.tar.gz"
                fi

                if [[ -n "${BUNJS_DOWNLOAD_URL}" ]] && \
                    curl -sLI "${BUNJS_DOWNLOAD_URL}" | grep -q "HTTP/[.12]* [2].."; then
                    run curl -sSL -o bun.tar.gz "${BUNJS_DOWNLOAD_URL}" && \
                    run tar -zxf bun.tar.gz && \
                    run cp -rf bun-linux-x64 /opt/bun && \
                    run ln -sf /opt/bun/bun /usr/local/bin/bun && \
                    run chmod 755 /usr/local/bin/bun
                else
                    error "An error occured while downloading Bun.js binary."
                fi

                run cd "${CURRENT_DIR}" || return 1
            ;;
            *)
                # Skip unsupported installation mode.
                error "Installer method not supported. Bun.js installation skipped."
            ;;
        esac

        # Configure Bun.js environment.
        if [[ "${DRYRUN}" != true ]]; then
            # Create Bun.js config directory.
            if [[ ! -d /etc/lemper/bun ]]; then
                run mkdir -p /etc/lemper/bun
            fi

            # Set up global bun.json configuration.
            cat > /etc/lemper/bun/bunfig.toml <<EOL
# LEMPer Bun.js Configuration
[install]
# Use frozen lockfile for reproducible builds
frozenLogFile = true

[run]
# Set default Node.js compatibility flags
nodeModulesPath = "./node_modules/@bun"

[paths]
# Global cache directory
cache = "/var/lib/bun/cache"
EOL

            # Create Bun.js global cache directory.
            if [[ ! -d /var/lib/bun ]]; then
                run mkdir -p /var/lib/bun/cache
            fi

            # Add bun to system PATH via profile.d.
            if [[ ! -f /etc/profile.d/bun.sh ]]; then
                cat > /etc/profile.d/bun.sh <<EOL
# Bun.js runtime environment
export BUN_INSTALL="/opt/bun"
export BUN_RUNTIME="bun"
case ":\${PATH}:" in
    *":/usr/local/bin:"*) ;;
    *) export PATH="/usr/local/bin:\${PATH}" ;;
esac
EOL
            fi

            # Create global Bun.js user for file permissions.
            if [[ -z $(getent passwd bun) ]]; then
                if [[ "${DRYRUN}" != true ]]; then
                    run groupadd -r bun 2>/dev/null || true
                    run useradd -r -M -g bun bun 2>/dev/null || true
                else
                    info "Create Bun.js user in dry run mode."
                fi
            fi
        else
            info "Bun.js configuration skipped in dry run mode."
        fi

        echo "Starting Bun.js runtime..."

        if [[ "${DRYRUN}" != true ]]; then
            if [[ $(command -v bun) && $(bun --version 2>/dev/null) ]]; then
                success "Bun.js runtime started successfully."
            else
                info "Something went wrong with Bun.js installation."
            fi
        else
            info "Bun.js runtime started successfully in dry run mode."
        fi
    else
        info "Bun.js runtime installation skipped."
    fi
}

echo "[Bun.js Runtime Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v bun) && "${FORCE_INSTALL}" != true ]]; then
    info "Bun.js runtime already exists, installation skipped."
else
    init_bunjs_install "$@"
fi
