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
# Add Redis repository.
##
function add_redis_repo() {
    lemper_load_module services/apt/catalog || return 1
    lemper_apt_prepare_repository redis || return 1
    lemper_exec apt-get update -q -y
}

##
# Prepare the Valkey package source.
# Valkey is a Redis-compatible fork (drop-in replacement) maintained by
# the Linux Foundation. Ubuntu 24.04+ and Debian 13 ship it directly;
# Debian 12 provides it through bookworm-backports.
##
function add_valkey_repo() {
    echo "Preparing Valkey installation..."

    if apt-cache show valkey-server >/dev/null 2>&1; then
        info "Valkey is available from the configured repositories."
        return 0
    fi

    if [[ "${DISTRIB_NAME}" == "debian" && "${RELEASE_NAME}" == "bookworm" ]]; then
        local BACKPORTS_LIST="/etc/apt/sources.list.d/lemper-backports.list"

        if [[ ! -f "${BACKPORTS_LIST}" ]]; then
            run bash -c "echo 'deb http://deb.debian.org/debian bookworm-backports main' > ${BACKPORTS_LIST}"
        fi

        run apt-get update -q -y

        if apt-cache show valkey-server >/dev/null 2>&1; then
            info "Valkey is available from Debian bookworm-backports."
            return 0
        fi
    fi

    fail "Valkey is not packaged for ${DISTRIB_NAME} ${RELEASE_NAME}. Use REDIS_BACKEND=\"redis\" or install Valkey from source."
}

# A fresh package must not start on host loopback before its config is ready.
function lemper_cache_install_gate() {
    local gate="$1" staged
    lemper_directory_trusted "${gate%/*}" || return 1
    lemper_exec install -d -m0755 "${gate%/*}" || return 1
    staged=$(mktemp "$gate.XXXXXXXX") || return 1
    if ! printf '%s\n' '# Managed by LEMPer' '[Unit]' \
        'ConditionPathExists=/run/lemper/cache-package-install-complete' > "$staged" ||
        ! chmod 0644 "$staged" || ! lemper_exec mv -Tf -- "$staged" "$gate"; then
        rm -f -- "$staged"
        return 1
    fi
    lemper_exec systemctl daemon-reload
}

# Publish the complete protected config atomically, with one managed settings block.
function lemper_cache_configure() {
    local backend="$1" config="$2" memory="$3" password="${4:-}" staged
    [[ -f "$config" && ! -L "$config" ]] && lemper_directory_trusted "${config%/*}" || return 1
    staged=$(mktemp "$config.XXXXXXXX") || return 1
    if ! awk -v replace_auth="${password:+true}" '
        /^# BEGIN LEMPer cache configuration$/ {managed=1; next}
        /^# END LEMPer cache configuration$/ {managed=0; next}
        !managed || (replace_auth != "true" && /^[[:space:]]*requirepass[[:space:]]/) {print}
    ' "$config" > "$staged" || ! {
        printf '\n%s\nmaxmemory %smb\n%s\n' '# BEGIN LEMPer cache configuration' \
            "$memory" 'maxmemory-policy allkeys-lru'
        if [[ -n "$password" ]]; then printf 'requirepass %s\n' "$password"; fi
        printf '%s\n' '# END LEMPer cache configuration'
    } >> "$staged" || ! chgrp "$backend" "$staged" || ! chmod 0640 "$staged" ||
        ! lemper_exec mv -Tf -- "$staged" "$config"; then
        rm -f -- "$staged"
        return 1
    fi
}

function lemper_cache_check_access() {
    local backend="$1" password="${2:-}" reply
    local -a client=(timeout 5 env -u REDISCLI_AUTH -u VALKEYCLI_AUTH -u REDIS_PASSWORD
        "${backend}-cli" --raw -h 127.0.0.1 -p 6379)
    reply=$("${client[@]}" PING 2>/dev/null) || return 1
    if [[ -n "$password" ]]; then
        [[ "$reply" == 'NOAUTH '* ]] || return 1
        reply=$(printf '%s' "$password" | "${client[@]}" -x AUTH 2>/dev/null) || return 1
        [[ "$reply" == OK ]]
    else
        [[ "$reply" == PONG || "$reply" == 'NOAUTH '* ]]
    fi
}

##
# Initialize Redis installation.
##
function init_redis_install {
    local SELECTED_INSTALLER=""
    local REDIS_BACKEND="${REDIS_BACKEND:-redis}"
    local cache_password="" cache_gate="" cache_config prepared ram memory

    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_REDIS}" == true ]]; then
            DO_INSTALL_REDIS="y"
            SELECTED_INSTALLER=${REDIS_INSTALLER:-"repo"}
        else
            DO_INSTALL_REDIS="n"
        fi
    else
        while [[ "${DO_INSTALL_REDIS}" != "y" && "${DO_INSTALL_REDIS}" != "n" ]]; do
            read -rp "Do you want to install Redis/Valkey server? [y/n]: " -i y -e DO_INSTALL_REDIS
        done
    fi

    if [[ ${DO_INSTALL_REDIS} == y* || ${DO_INSTALL_REDIS} == Y* ]]; then
        # Select backend (Redis or Valkey).
        if [[ "${AUTO_INSTALL}" == true ]]; then
            REDIS_BACKEND="${REDIS_BACKEND:-redis}"
        else
            while [[ "${REDIS_BACKEND}" != "redis" && "${REDIS_BACKEND}" != "valkey" ]]; do
                read -rp "Select backend [redis/valkey]: " -i redis -e REDIS_BACKEND
            done
        fi

        if [[ "${REDIS_BACKEND}" == "valkey" ]]; then
            echo "Installing Valkey (Redis-compatible fork)..."
        else
            echo "Installing Redis server..."
        fi

        # Install menu.
        echo "Available installation method:"
        echo "  1). Install from Repository (repo)"
        echo "  2). Compile from Source (source)"
        echo "-------------------------------------"

        while [[ ${SELECTED_INSTALLER} != "1" && ${SELECTED_INSTALLER} != "2" && ${SELECTED_INSTALLER} != "none" &&
            ${SELECTED_INSTALLER} != "repo" && ${SELECTED_INSTALLER} != "source" ]]; do
            read -rp "Select an option [1-2]: " -e SELECTED_INSTALLER
        done

        if [[ "${SELECTED_INSTALLER}" == none ]]; then
            info "Redis/Valkey server installation skipped."
            return 0
        fi
        if [[ "${DRYRUN:-false}" == true ]]; then
            info "Would install and configure ${REDIS_BACKEND}."
            return 0
        fi
        if [[ "${REDIS_REQUIRE_PASSWORD:-true}" == true ]]; then
            cache_password="${REDIS_PASSWORD:-$(openssl rand -hex 32)}"
            if [[ ! "$cache_password" =~ ^[A-Za-z0-9_.+-]{16,256}$ ]]; then
                error "Cache authentication requires a password of at least 16 supported characters."
                return 1
            fi
        fi
        cache_gate="/etc/systemd/system/${REDIS_BACKEND}-server.service.d/90-lemper-install.conf"
        if ! command -v "${REDIS_BACKEND}-server" >/dev/null || [[ -f "$cache_gate" ]]; then
            lemper_cache_install_gate "$cache_gate" || return 1
        else
            cache_gate=""
        fi

        case "${SELECTED_INSTALLER}" in
            1 | "repo")
                if [[ "${REDIS_BACKEND}" == "valkey" ]]; then
                    # Add Valkey repos.
                    add_valkey_repo || return 1

                    echo "Installing Valkey server from repository..."

                    # Install Valkey (Redis-compatible).
                    run_spinner "Installing Valkey" apt-get install -q -y valkey-server valkey-tools || return 1
                else
                    # Add Redis repos.
                    add_redis_repo || return 1

                    echo "Installing Redis server from repository..."

                    # Install Redis.
                    run_spinner "Installing Redis" apt-get install -q -y redis redis-server redis-tools || return 1
                fi
                ;;
            2 | "source")
                lemper_build_workspace "${BUILD_DIR}" || return 1
                if [[ "${REDIS_BACKEND}" == "valkey" ]]; then
                    echo "Installing Valkey server from source..."

                    local CURRENT_DIR \
                        && CURRENT_DIR=$(pwd)
                    run cd "${BUILD_DIR}" || error "Cannot change directory to ${BUILD_DIR}"

                    if [[ "${REDIS_VERSION}" == "latest" || "${REDIS_VERSION}" == "stable" ]]; then
                        VALKEY_DOWNLOAD_URL="https://github.com/valkey-io/valkey/archive/refs/tags/stable.tar.gz"
                    else
                        VALKEY_DOWNLOAD_URL="https://github.com/valkey-io/valkey/archive/refs/tags/valkey-${REDIS_VERSION}.tar.gz"
                    fi

                    if curl -sLI "${VALKEY_DOWNLOAD_URL}" | grep -q "HTTP/[.12]* [2].."; then
                        run curl -sSL -o valkey.tar.gz "${VALKEY_DOWNLOAD_URL}" \
                            && run tar -zxf valkey.tar.gz \
                            && run cd valkey-* \
                            && run_spinner "Compiling Valkey" make \
                            && run_spinner "Installing Valkey" make install

                        # Create Valkey user.
                        if [[ -z $(getent passwd valkey) ]]; then
                            if [[ "${DRYRUN}" != true ]]; then
                                run groupadd -r valkey
                                run useradd -r -M -g valkey valkey
                            else
                                info "Create Valkey user in dry run mode."
                            fi
                        fi

                        if [[ ! -d /etc/valkey ]]; then
                            run mkdir /etc/valkey
                        fi

                        if [[ ! -d /run/valkey ]]; then
                            run mkdir /run/valkey
                            run chown valkey:valkey /run/valkey
                            run chmod 770 /run/valkey
                        fi
                    else
                        error "An error occured while downloading Valkey source."
                        return 1
                    fi

                    run cd "${CURRENT_DIR}" || return 1
                else
                    echo "Installing Redis server from source..."

                    local CURRENT_DIR \
                        && CURRENT_DIR=$(pwd)
                    run cd "${BUILD_DIR}" || return 1

                    local redis_download_url
                    if [[ "${REDIS_VERSION}" == "latest" || "${REDIS_VERSION}" == "stable" ]]; then
                        redis_download_url="https://download.redis.io/redis-stable.tar.gz"
                    else
                        redis_download_url="https://download.redis.io/releases/redis-${REDIS_VERSION}.tar.gz"
                    fi

                    if run curl -q -fsSL --proto '=https' --proto-redir '=https' -o redis.tar.gz "$redis_download_url"; then
                        run tar -zxf redis.tar.gz \
                            && run cd redis-*/ \
                            && run_spinner "Compiling Redis" make \
                            && run_spinner "Installing Redis" make install || return 1

                        # Create Redis user.
                        if [[ -z $(getent passwd redis) ]]; then
                            if [[ "${DRYRUN}" != true ]]; then
                                run groupadd -r redis
                                run useradd -r -M -g redis redis
                            else
                                info "Create Redis user in dry run mode."
                            fi
                        fi

                        if [[ ! -d /etc/redis ]]; then
                            run mkdir /etc/redis
                        fi

                        if [[ ! -d /run/redis ]]; then
                            run mkdir /run/redis
                            run chown redis:redis /run/redis
                            run chmod 770 /run/redis
                        fi
                    else
                        error "An error occured while downloading Redis source."
                        return 1
                    fi

                    run cd "${CURRENT_DIR}" || return 1
                fi
                ;;
            *)
                # Skip unsupported installation mode.
                error "Installer method not supported. Redis/Valkey installation skipped."
                return 1
                ;;
        esac

        # Keep the vendor config and service when installed from packages.
        if [[ "${REDIS_BACKEND}" == valkey ]]; then
            local VALKEY_CONF="/etc/valkey/valkey.conf"
            cache_config="$VALKEY_CONF"
            if [[ ! -f "${VALKEY_CONF}" ]]; then
                lemper_exec install -d -m0755 /etc/valkey || return 1
                lemper_exec install -m0640 -g valkey etc/redis/redis.conf "$VALKEY_CONF" || return 1
                sed_inplace "s|/var/run/redis/|/var/run/valkey/|g" "$VALKEY_CONF"
                sed_inplace "s|/var/log/redis/|/var/log/valkey/|g" "$VALKEY_CONF"
                sed_inplace "s|/var/lib/redis|/var/lib/valkey|g" "$VALKEY_CONF"
                sed_inplace "s|redis-server.pid|valkey-server.pid|g" "$VALKEY_CONF"
                sed_inplace "s|redis-server.log|valkey-server.log|g" "$VALKEY_CONF"
            fi
        else
            cache_config=/etc/redis/redis.conf
            if [[ ! -f "$cache_config" ]]; then
                lemper_exec install -d -m0755 /etc/redis || return 1
                lemper_exec install -m0640 -g redis etc/redis/redis.conf "$cache_config" || return 1
            fi
        fi
        if [[ "$SELECTED_INSTALLER" == 2 || "$SELECTED_INSTALLER" == source ]]; then
            local service_directory="/var/lib/${REDIS_BACKEND}" log_directory="/var/log/${REDIS_BACKEND}"
            lemper_exec install -d -o "$REDIS_BACKEND" -g "$REDIS_BACKEND" -m0750 "$service_directory" "$log_directory" || return 1
        fi
        ram=$(get_ram_size) || return 1
        [[ "$ram" =~ ^[0-9]+$ ]] || return 1
        if (( ram <= 2048 )); then
            memory=$((ram / 8))
        elif (( ram <= 8192 )); then
            memory=$((ram / 4))
        else
            memory=2048
        fi
        lemper_cache_configure "$REDIS_BACKEND" "$cache_config" "$memory" "$cache_password" || return 1

        if [[ -n "$cache_password" ]]; then
            init_config || return 1
            lemper_load_module core/config-update || return 1
            prepared=$(core_config_prepare_value /etc/lemper/lemper.conf REDIS_PASSWORD "$cache_password") || return 1
            if [[ -n "$prepared" ]] && ! lemper_exec mv -Tf -- "$prepared" /etc/lemper/lemper.conf; then
                secure_shred "$prepared"
                return 1
            fi
            REDIS_PASSWORD="$cache_password"
            export -n REDIS_PASSWORD
        fi

        local unit="${REDIS_BACKEND}-server.service"
        if [[ ! -f "/lib/systemd/system/$unit" ]]; then
            lemper_exec install -m0644 "etc/systemd/$unit" "/lib/systemd/system/$unit" || return 1
            if [[ "$SELECTED_INSTALLER" == 2 || "$SELECTED_INSTALLER" == source ]]; then
                sed_inplace "s|/usr/bin/${REDIS_BACKEND}-server|/usr/local/bin/${REDIS_BACKEND}-server|g" "/lib/systemd/system/$unit"
            fi
        fi
        if [[ "$REDIS_BACKEND" == redis && ! -f /etc/init.d/redis-server ]]; then
            lemper_exec install -m0755 etc/init.d/redis-server /etc/init.d/redis-server || return 1
        fi
        if [[ -n "$cache_gate" ]]; then
            lemper_exec rm -f -- "$cache_gate" || return 1
        fi
        lemper_exec systemctl daemon-reload || return 1
        if ! lemper_exec systemctl restart "$unit" || ! systemctl is-active --quiet "$unit" ||
            ! lemper_cache_check_access "$REDIS_BACKEND" "$cache_password"; then
            lemper_exec systemctl stop "$unit"
            [[ -z "$cache_gate" ]] || lemper_cache_install_gate "$cache_gate"
            error "Cache access policy could not be verified. The service was stopped."
            return 1
        fi
        lemper_exec systemctl enable "$unit" || return 1
        success "Cache started with its configured access policy."
    else
        info "Redis/Valkey server installation skipped."
    fi
}

function lemper_redis_install_entry() {
    echo "[Redis/Valkey Server Installation]"
    local backend="${REDIS_BACKEND:-redis}" other
    case "$backend" in
        redis) other=valkey ;;
        valkey) other=redis ;;
        *) error "Unsupported cache backend."; return 1 ;;
    esac
    if ! command -v "${backend}-server" >/dev/null && command -v "${other}-server" >/dev/null; then
        info "Preserving the installed ${other} server. Migrate it before selecting ${backend}."
        return 0
    fi
    if command -v "${backend}-server" >/dev/null && [[ "${FORCE_INSTALL:-false}" != true &&
        ! -f "/etc/systemd/system/${backend}-server.service.d/90-lemper-install.conf" ]]; then
        info "Redis/Valkey server already exists, installation skipped."
    else
        init_redis_install "$@"
    fi
}
