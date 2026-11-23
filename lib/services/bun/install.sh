#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Shared Security Helpers                                          |
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
            SELECTED_INSTALLER=${BUNJS_INSTALLER:-"source"}
        else
            DO_INSTALL_BUNJS="n"
        fi
    else
        while [[ "${DO_INSTALL_BUNJS}" != "y" && "${DO_INSTALL_BUNJS}" != "Y" &&
            "${DO_INSTALL_BUNJS}" != "n" && "${DO_INSTALL_BUNJS}" != "N" ]]; do
            read -rp "Do you want to install Bun.js runtime? [y/n]: " -e DO_INSTALL_BUNJS
        done
    fi

    if [[ ${DO_INSTALL_BUNJS} == y* || ${DO_INSTALL_BUNJS} == Y* ]]; then
        echo "Available Bun.js installation method:"
        echo "  1). Install from Repository (repo) — apt package"
        echo "  2). Compile from Source (source) — official binary release"
        echo "-------------------------------------"

        while [[ "${SELECTED_INSTALLER}" != "1" && "${SELECTED_INSTALLER}" != "2" &&
            "${SELECTED_INSTALLER}" != "repo" && "${SELECTED_INSTALLER}" != "source" ]]; do
            read -rp "Select an option [1-2]: " -i "${BUNJS_INSTALLER:-source}" -e SELECTED_INSTALLER
        done

        case "${SELECTED_INSTALLER}" in
            1 | "repo")
                warning "The former Bun APT endpoint is retired; using the verified official release binary."
                lemper_load_module services/bun/binary || return 1
                lemper_bun_install_binary || return 1
                ;;
            2 | "source")
                lemper_load_module services/bun/binary || return 1
                lemper_bun_install_binary || return 1
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
            cat >/etc/lemper/bun/bunfig.toml <<EOL
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
                cat >/etc/profile.d/bun.sh <<EOL
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

function lemper_bun_install_entry() {
    echo "[Bun.js Runtime Installation]"
    if [[ -n $(command -v bun) && "${FORCE_INSTALL}" != true ]]; then
        info "Bun.js runtime already exists, installation skipped."
    else
        init_bunjs_install "$@"
    fi
}
