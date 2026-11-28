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

function lemper_memcached_disable_default() {
    if systemctl is-active --quiet memcached.service; then
        lemper_exec systemctl stop memcached.service || return 1
    fi
    lemper_exec systemctl mask memcached.service
}

function lemper_memcached_configure_sasl() {
    local directory=/etc/lemper-memcached stage username="${MEMCACHED_USERNAME:-lempermc}"
    local password="${MEMCACHED_PASSWORD:-}"
    [[ "$username" =~ ^[a-zA-Z0-9_.-]+$ && -n "$password" && ! "$password" =~ [[:cntrl:]] ]] || {
        error "Set a valid Memcached SASL username and password before enabling its TCP listener."
        return 1
    }
    lemper_directory_trusted "$directory" || return 1
    install -d -o root -g memcache -m0750 "$directory" || return 1
    stage=$(mktemp -d "$directory/.sasl.XXXXXXXX") || return 1
    if ! (
        umask 077
        printf '%s\n' 'mech_list: plain' 'pwcheck_method: auxprop' 'auxprop_plugin: sasldb' \
            "sasldb_path: $directory/sasldb" >"$stage/memcached.conf" \
            && printf '%s\n' "$password" | saslpasswd2 -p -a memcached -f "$stage/sasldb" -c "$username" \
            && chown root:memcache "$stage/memcached.conf" "$stage/sasldb" \
            && chmod 0640 "$stage/memcached.conf" "$stage/sasldb" \
            && mv -T "$stage/sasldb" "$directory/sasldb" \
            && mv -T "$stage/memcached.conf" "$directory/memcached.conf"
    ); then
        rm -rf -- "$stage"
        return 1
    fi
    rmdir "$stage"
}

function lemper_memcached_render_config() {
    local instance="$1" mode="$2" template="$3" memory="$4"
    case "$instance:$mode" in
        memcache:sasl)
            sed -e '/^-p 0$/d' -e '/^-s /d' -e '/^-a /d' \
                -e "s/^-m 64$/-m $memory/" "$template" || return 1
            printf '%s\n' '-l 127.0.0.1' '-p 11211' '-B binary' '-S'
            ;;
        memcache:socket | www-data:socket) sed -e "s/^-m 64$/-m $memory/" "$template" ;;
        *) return 1 ;;
    esac
}

function lemper_memcached_set_endpoints() {
    local root stage instance mode=socket memory ram path pidfile
    if [[ "${DRYRUN:-false}" == true ]]; then
        info "Would switch LEMPer Memcached instances to their managed endpoints."
        return 0
    fi
    root=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../.." && pwd) || return 1
    ram=$(get_ram_size) || return 1
    [[ "$ram" =~ ^[1-9][0-9]*$ ]] || return 1
    if ((ram <= 2048)); then
        memory=$((ram / 16))
    elif ((ram <= 8192)); then
        memory=$((ram / 8))
    else
        memory=2048
    fi
    ((memory >= 4)) || memory=4
    if [[ "${MEMCACHED_SASL:-false}" =~ ^(true|enable)$ ]]; then
        command -v saslpasswd2 >/dev/null || {
            error "Install sasl2-bin to enable Memcached SASL."
            return 1
        }
        lemper_memcached_configure_sasl || return 1
        mode=sasl
    fi
    stage=$(mktemp -d /etc/.lemper-memcached.XXXXXXXX) || return 1
    if ! (
        trap 'rm -rf -- "$stage"' EXIT
        lemper_memcached_render_config memcache "$mode" "$root/etc/memcached/memcache.conf" "$memory" >"$stage/memcache.conf" \
            && lemper_memcached_render_config www-data socket "$root/etc/memcached/www-data.conf" "$memory" >"$stage/www-data.conf" || return 1
        lemper_memcached_disable_default || return 1

        install -d -m0755 /usr/local/lib/lemper/memcached || return 1
        install -m0755 "$root"/share/memcached/scripts/{systemd-memcached-wrapper,start-memcached,memcached-tool,damemtop} \
            /usr/local/lib/lemper/memcached/ || return 1
        install -m0644 "$root"/share/memcached/scripts/{config.bash,client.bash,damemtop.yaml} \
            /usr/local/lib/lemper/memcached/ || return 1
        if ! systemctl cat memcached@memcache.service >/dev/null 2>&1; then
            install -m0644 "$root/etc/systemd/memcached@.service" /etc/systemd/system/memcached@.service || return 1
        fi

        for instance in memcache www-data; do
            path="/etc/memcached_$instance.conf"
            if [[ -f "$path" && ! -e "$path.lemper-before-endpoints" ]]; then
                cp -p -- "$path" "$path.lemper-before-endpoints" || return 1
            fi
            pidfile="/run/memcached_$instance.pid"
            if [[ -f "$pidfile" && ! -L "$pidfile" ]]; then
                # The old compatibility launcher tracked only these instances.
                start-stop-daemon --stop --quiet --oknodo --retry 5 --pidfile "$pidfile" \
                    --exec /usr/bin/memcached --user "$instance" || return 1
            fi
            install -m0644 "$stage/$instance.conf" "$path" || return 1
            install -Dm0644 "$root/etc/systemd/memcached-runtime.conf" \
                "/etc/systemd/system/memcached@$instance.service.d/10-lemper-endpoints.conf" || return 1
        done
        systemctl daemon-reload \
            && systemctl enable memcached@memcache.service memcached@www-data.service \
            && systemctl restart memcached@memcache.service memcached@www-data.service \
            && systemctl is-active --quiet memcached@memcache.service \
            && systemctl is-active --quiet memcached@www-data.service
    ); then
        error "Could not activate the managed Memcached endpoints."
        return 1
    fi
    success "Managed Memcached endpoints are active."
}

function lemper_memcached_migrate_endpoints() {
    [[ -x /usr/local/lib/lemper/memcached/start-memcached &&
        -f /etc/memcached_memcache.conf && -f /etc/memcached_www-data.conf ]] || {
        error "A LEMPer-managed Memcached installation is required."
        return 1
    }
    lemper_memcached_set_endpoints
}

##
# Initialize Memcached Installation.
##
function init_memcached_install() {
    local MEMCACHED_LIBRARY_PACKAGES=(libmemcached11 libmemcachedutil2)
    if [[ "${DISTRIB_NAME}/${RELEASE_NAME}" == ubuntu/resolute ]]; then
        MEMCACHED_LIBRARY_PACKAGES=(libmemcached11t64 libmemcachedutil2t64)
    fi
    local SELECTED_INSTALLER=""

    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_MEMCACHED}" == true ]]; then
            DO_INSTALL_MEMCACHED="y"
            SELECTED_INSTALLER=${MEMCACHED_INSTALLER:-"repo"}
        else
            DO_INSTALL_MEMCACHED="n"
        fi
    else
        while [[ "${DO_INSTALL_MEMCACHED}" != "y" && "${DO_INSTALL_MEMCACHED}" != "n" ]]; do
            read -rp "Do you want to install Memcached server? [y/n]: " -i y -e DO_INSTALL_MEMCACHED
        done
    fi

    if [[ ${DO_INSTALL_MEMCACHED} == y* || ${DO_INSTALL_MEMCACHED} == Y* ]]; then
        # Install menu.
        if [[ "${AUTO_INSTALL}" != true ]]; then
            echo "Available Memcached installation method:"
            echo "  1). Install from Repository (repo)"
            echo "  2). Compile from Source (source)"
            echo "-------------------------------------"

            while [[ ${SELECTED_INSTALLER} != "1" && ${SELECTED_INSTALLER} != "2" && ${SELECTED_INSTALLER} != "none" &&
                ${SELECTED_INSTALLER} != "repo" && ${SELECTED_INSTALLER} != "source" ]]; do
                read -rp "Select an option [1-2]: " -e SELECTED_INSTALLER
            done
        fi

        if [[ "${SELECTED_INSTALLER}" =~ ^(1|2|repo|source)$ ]]; then
            lemper_memcached_disable_default || return 1
        fi
        local sasl_packages=()
        [[ ! "${MEMCACHED_SASL:-false}" =~ ^(true|enable)$ ]] || sasl_packages=(sasl2-bin)
        case "${SELECTED_INSTALLER}" in
            1 | repo)
                echo "Installing Memcached server from repository..."

                run apt-get install -q -y \
                    libevent-dev libsasl2-dev libmemcached-tools "${MEMCACHED_LIBRARY_PACKAGES[@]}" "${sasl_packages[@]}" memcached socat
                ;;
            2 | source)
                echo "Installing Memcached server from source..."

                run apt-get install -q -y \
                    libevent-dev libsasl2-dev libmemcached-tools "${MEMCACHED_LIBRARY_PACKAGES[@]}" "${sasl_packages[@]}" socat

                local CURRENT_DIR \
                    && CURRENT_DIR=$(pwd)

                lemper_build_workspace "${BUILD_DIR}" || return 1
                run cd "${BUILD_DIR}" || return 1
                local memcached_download_url
                if [[ "${MEMCACHED_VERSION}" == "latest" || "${MEMCACHED_VERSION}" == "stable" ]]; then
                    memcached_download_url="https://memcached.org/latest"
                else
                    memcached_download_url="https://memcached.org/files/memcached-${MEMCACHED_VERSION}.tar.gz"
                fi

                run curl -q -fsSL --proto '=https' --proto-redir '=https' -o memcached.tar.gz "$memcached_download_url" \
                    && run tar -zxf memcached.tar.gz && run cd memcached-*/ || return 1
                if [[ "${MEMCACHED_SASL}" == "enable" || "${MEMCACHED_SASL}" == true ]]; then
                    run ./configure --enable-sasl --bindir=/usr/bin || return 1
                else
                    run ./configure --bindir=/usr/bin || return 1
                fi
                run make && run make install || return 1

                # Create memcache user.
                if [[ -z $(getent passwd memcache) ]]; then
                    if [[ "${DRYRUN}" != true ]]; then
                        run groupadd -r memcache
                        run useradd -r -M -g memcache memcache
                    else
                        echo "Create memcache user in dry run mode."
                    fi
                fi

                run cd "${CURRENT_DIR}" || return 1
                ;;
            *)
                # Skip installation.
                error "Installer method not supported. Memcached installation skipped."
                return 1
                ;;
        esac

        if [[ "${DRYRUN:-false}" != true && ! -x /usr/bin/memcached ]]; then
            error "Memcached server executable is missing."
            return 1
        fi
        if [[ "${MEMCACHED_SASL:-false}" =~ ^(true|enable)$ && "${DRYRUN:-false}" != true ]]; then
            local settings
            MEMCACHED_USERNAME="${MEMCACHED_USERNAME:-lempermc}"
            MEMCACHED_PASSWORD="${MEMCACHED_PASSWORD:-$(openssl rand -hex 24)}"
            lemper_memcached_set_endpoints || return 1
            printf -v settings '%s\n' "MEMCACHED_SASL=$MEMCACHED_SASL" "MEMCACHED_USERNAME=$MEMCACHED_USERNAME" \
                "MEMCACHED_PASSWORD=$MEMCACHED_PASSWORD" 'MEMCACHED_INSTANCE=memcache'
            save_config "$settings"
        else
            lemper_memcached_set_endpoints
        fi
    else
        info "Memcached server installation skipped."
    fi
}

function lemper_memcached_install_entry() {
    echo "[Memcached Server Installation]"
    if [[ -n $(command -v memcached) && "${FORCE_INSTALL}" != true ]]; then
        info "Memcached server already exists, installation skipped."
    else
        init_memcached_install "$@"
    fi
}
