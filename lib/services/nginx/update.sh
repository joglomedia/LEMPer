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
# True when the nginx binary on PATH comes from a .deb.
##
function nginx_is_package_managed() {
    local bin="" real=""
    bin=$(command -v nginx 2>/dev/null || true)
    [[ -n "${bin}" ]] || return 1
    real=$(readlink -f "${bin}" 2>/dev/null || printf '%s' "${bin}")
    dpkg -S "${real}" >/dev/null 2>&1
}

##
# MyGuard package that replaces an Ondřej module name.
# libnginx-mod-rtmp is published under the same name and is not rewritten.
##
function nginx_myguard_module_target() {
    case "${1}" in
        libnginx-mod-brotli) printf '%s\n' "libnginx-mod-http-brotli" ;;
        *) printf '%s\n' "${1}" ;;
    esac
}

##
# Print the candidate version, or fail when apt has none.
##
function nginx_apt_candidate() {
    local cand=""
    cand=$(apt-cache policy "${1}" 2>/dev/null | awk '/^[[:space:]]*Candidate:/ {print $2; exit}' || true)
    [[ -n "${cand}" && "${cand}" != "(none)" ]] || return 1
    printf '%s\n' "${cand}"
}

##
# Upgrade installed nginx packages (source builds must be rebuilt).
# Package installs move to the MyGuard nginx-only repository. /etc/nginx is kept.
##
function update_nginx() {
    local bin="" real="" pkg="" target="" name=""
    local install_list=" nginx nginx-common "
    local remove_list=" "
    local -a txn=()

    bin=$(command -v nginx 2>/dev/null || true)
    if [[ -z "${bin}" ]]; then
        info "nginx is not installed."
        return 0
    fi

    real=$(readlink -f "${bin}" 2>/dev/null || echo "${bin}")
    if ! dpkg -S "${real}" >/dev/null 2>&1; then
        warning "nginx at ${bin} is not package-managed (source build); rebuild nginx to apply updates."
        return 1
    fi

    while IFS= read -r pkg; do
        [[ -z "${pkg}" ]] && continue
        case "${pkg}" in
            nginx | nginx-common) continue ;;
        esac
        target=$(nginx_myguard_module_target "${pkg}")
        if nginx_apt_candidate "${target}" >/dev/null; then
            case "${install_list}" in
                *" ${target} "*) ;;
                *) install_list+="${target} " ;;
            esac
            if [[ "${target}" != "${pkg}" ]]; then
                case "${remove_list}" in
                    *" ${pkg} "*) ;;
                    *) remove_list+="${pkg} " ;;
                esac
            fi
        else
            warning "No MyGuard package for ${pkg}; removing it so the nginx ABI can change."
            case "${remove_list}" in
                *" ${pkg} "*) ;;
                *) remove_list+="${pkg} " ;;
            esac
        fi
    done < <(dpkg-query -W -f='${Package}\n' 'nginx*' 'libnginx-mod-*' 2>/dev/null || true)

    # shellcheck disable=SC2086
    for name in ${install_list}; do
        txn+=("${name}")
    done
    # shellcheck disable=SC2086
    for name in ${remove_list}; do
        txn+=("${name}-")
    done

    warning "Upgrading package-managed nginx from the MyGuard nginx repository (mainline, linked to libssl-nginx). Existing /etc/nginx files are kept. Switching an Ondřej nginx install to MyGuard has not been verified on a live host."
    if [[ "${remove_list}" != " " ]]; then
        warning "Packages removed with this upgrade:${remove_list}"
    fi

    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
        -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold \
        "${txn[@]}"; then
        error "Failed to upgrade nginx packages."
        return 1
    fi

    if nginx -t; then
        if systemctl reload nginx 2>/dev/null; then
            success "nginx upgraded and reloaded."
        else
            warning "nginx upgraded, but reload failed; run 'systemctl reload nginx'."
        fi
    else
        error "nginx configuration test failed; not reloading."
        return 1
    fi
}
