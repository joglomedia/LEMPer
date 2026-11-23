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
# True when a sources line points at the unpublished Ondřej nginx archive.
# The Ondřej PHP archive shares the same host and must not match.
##
function nginx_line_is_retired_ondrej() {
    local line="${1}"

    [[ "${line}" =~ ^[[:space:]]*# ]] && return 1
    [[ "${line}" =~ ^[[:space:]]*$ ]] && return 1
    [[ "${line}" =~ ondrej/php(/|[[:space:]]|$) ]] && return 1
    [[ "${line}" =~ packages\.sury\.org/php(/|[[:space:]]|$) ]] && return 1
    [[ "${line}" =~ packages\.sury\.org/nginx(-mainline)?(/|[[:space:]]|$) ]] && return 0
    [[ "${line}" =~ ondrej/nginx(-mainline)?(/|[[:space:]]|$) ]] && return 0
    return 1
}

##
# True when the file contains a retired Ondřej nginx line.
##
function apt_file_has_retired_nginx() {
    local line
    [[ -f "${1}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if nginx_line_is_retired_ondrej "${line}"; then
            return 0
        fi
    done <"${1}"
    return 1
}

##
# True when every active entry in the file is a retired Ondřej nginx source.
##
function apt_file_is_only_retired_nginx() {
    local line retired=0 other=0
    [[ -f "${1}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if nginx_line_is_retired_ondrej "${line}"; then
            retired=1
            continue
        fi
        [[ "${line}" =~ ^[[:space:]]*(#|$) ]] && continue
        if [[ "${line}" =~ ondrej/php || "${line}" =~ packages\.sury\.org/php ]]; then
            other=1
            continue
        fi
        if [[ "${line}" =~ ^[[:space:]]*deb(-src)?[[:space:]] ]]; then
            other=1
            continue
        fi
        if [[ "${line}" =~ ^[[:space:]]*(Types|URIs|Suites|Components|Signed-By|Architectures|Enabled|Trusted|Allow-Insecure|Check-Valid-Until|By-Hash|PDiffs|X-[A-Za-z0-9-]+):[[:space:]] ]]; then
            continue
        fi
        other=1
    done <"${1}"
    [[ "${retired}" -eq 1 && "${other}" -eq 0 ]]
}

##
# True when a deb822 stanza still names the retired nginx archive.
##
function nginx_text_has_retired_nginx() {
    local line
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if nginx_line_is_retired_ondrej "${line}"; then
            return 0
        fi
    done <<<"${1}"
    return 1
}

##
# Comment retired nginx lines and leave every other entry in place.
##
function nginx_comment_retired_lines() {
    local src="${1}" tmp line changed=0
    tmp=$(mktemp "${TMPDIR:-/tmp}/lemper-apt.XXXXXX") || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if nginx_line_is_retired_ondrej "${line}"; then
            printf '# lemper-retired-ondrej-nginx: %s\n' "${line}" >>"${tmp}" || {
                rm -f "${tmp}"
                return 1
            }
            changed=1
        else
            printf '%s\n' "${line}" >>"${tmp}" || {
                rm -f "${tmp}"
                return 1
            }
        fi
    done <"${src}"
    if [[ "${changed}" -eq 0 ]]; then
        rm -f "${tmp}"
        return 0
    fi
    if ! cat "${tmp}" >"${src}"; then
        rm -f "${tmp}"
        return 1
    fi
    rm -f "${tmp}"
    info "Commented retired Ondřej nginx entries in ${src}"
}

##
# Drop deb822 stanzas that name the retired nginx archive.
##
function nginx_strip_retired_stanzas() {
    local src="${1}" tmp line stanza="" kept="" removed=0
    tmp=$(mktemp "${TMPDIR:-/tmp}/lemper-apt.XXXXXX") || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ -z "${line}" ]]; then
            if [[ -n "${stanza}" ]]; then
                if nginx_text_has_retired_nginx "${stanza}"; then
                    removed=1
                else
                    kept+="${stanza}"$'\n'
                fi
                stanza=""
            fi
            continue
        fi
        stanza+="${line}"$'\n'
    done <"${src}"
    if [[ -n "${stanza}" ]]; then
        if nginx_text_has_retired_nginx "${stanza}"; then
            removed=1
        else
            kept+="${stanza}"
        fi
    fi
    if [[ "${removed}" -eq 0 ]]; then
        rm -f "${tmp}"
        return 0
    fi
    if [[ -z "${kept//[[:space:]]/}" ]]; then
        rm -f "${tmp}"
        if [[ -e "${src}.disabled" ]]; then
            info "Retired Ondřej nginx source already disabled: ${src}.disabled"
            return 0
        fi
        mv "${src}" "${src}.disabled" || return 1
        info "Disabled retired Ondřej nginx source: ${src}"
        return 0
    fi
    printf '%s' "${kept}" >"${tmp}" || {
        rm -f "${tmp}"
        return 1
    }
    if ! cat "${tmp}" >"${src}"; then
        rm -f "${tmp}"
        return 1
    fi
    rm -f "${tmp}"
    info "Removed retired Ondřej nginx stanza from ${src}"
}

##
# Disable unpublished Ondřej nginx APT sources before apt-get update.
# Drop-in files that contain only that archive are renamed to .disabled.
# The Ondřej PHP source is left enabled.
##
function retire_ondrej_nginx_sources() {
    local root="${LEMPER_APT_ROOT:-/etc/apt}"
    local entry f
    local -a files=()

    if [[ -f "${root}/sources.list" ]]; then
        files+=("${root}/sources.list")
    fi
    if [[ -d "${root}/sources.list.d" ]]; then
        for entry in "${root}/sources.list.d"/*; do
            [[ -f "${entry}" ]] || continue
            case "${entry}" in
                *.disabled) continue ;;
                *.list | *.sources) files+=("${entry}") ;;
            esac
        done
    fi

    for f in "${files[@]}"; do
        if apt_file_is_only_retired_nginx "${f}"; then
            if [[ -e "${f}.disabled" ]]; then
                info "Retired Ondřej nginx source already disabled: ${f}.disabled"
                continue
            fi
            mv "${f}" "${f}.disabled" || return 1
            info "Disabled retired Ondřej nginx source: ${f}"
            continue
        fi
        if ! apt_file_has_retired_nginx "${f}"; then
            continue
        fi
        case "${f}" in
            *.sources)
                nginx_strip_retired_stanzas "${f}" || return 1
                ;;
            *)
                nginx_comment_retired_lines "${f}" || return 1
                ;;
        esac
    done
}

##
# Distribution codename used in the MyGuard suite name.
##
function nginx_release_codename() {
    local codename=""
    if [[ -n "${LEMPER_NGINX_CODENAME:-}" ]]; then
        printf '%s\n' "${LEMPER_NGINX_CODENAME}"
        return 0
    fi
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        codename="${VERSION_CODENAME:-}"
    fi
    if [[ -z "${codename}" ]]; then
        return 1
    fi
    printf '%s\n' "${codename}"
}

##
# Architectures published in the MyGuard nginx tree.
##
function nginx_apt_arch() {
    local arch=""
    if [[ -n "${LEMPER_NGINX_ARCH:-}" ]]; then
        printf '%s\n' "${LEMPER_NGINX_ARCH}"
        return 0
    fi
    if command -v dpkg >/dev/null 2>&1; then
        arch=$(dpkg --print-architecture 2>/dev/null || true)
    fi
    if [[ -z "${arch}" ]]; then
        arch="amd64"
    fi
    printf '%s\n' "${arch}"
}

##
# MyGuard publishes nginx packages for these suites.
##
function nginx_codename_supported() {
    case "${1}" in
        focal | jammy | noble | resolute | bullseye | bookworm | trixie)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

##
# deb line for the nginx-only tree. The flat http://deb.myguard.nl layout is retired.
##
function myguard_nginx_source_line() {
    local root="${LEMPER_APT_ROOT:-/etc/apt}"
    local codename arch
    codename=$(nginx_release_codename) || return 1
    arch=$(nginx_apt_arch)
    printf 'deb [arch=%s signed-by=%s/keyrings/deb.myguard.nl.gpg] https://deb.myguard.nl/apt/nginx/%s %s main\n' \
        "${arch}" "${root}" "${codename}" "${codename}"
}

##
# Prefer MyGuard only for nginx and the libraries that nginx package depends on.
##
function myguard_nginx_pin_text() {
    cat <<'EOF'
Package: nginx nginx-common nginx-core nginx-full nginx-extras nginx-light nginx-minimal libnginx-mod-* libssl-nginx libssl-nginx-dev libz-ng2
Pin: origin "deb.myguard.nl"
Pin-Priority: 501
EOF
}

##
# True when the keyring file matches the published MyGuard fingerprint.
##
function myguard_nginx_key_fingerprint() {
    local key="${1}" fp=""
    # The published file is a raw OpenPGP certificate, not a keybox.
    fp=$(gpg --batch --with-colons --show-keys "${key}" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}' || true)
    if [[ -z "${fp}" ]]; then
        fp=$(gpg --batch --with-colons --import-options show-only --import "${key}" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}' || true)
    fi
    printf '%s\n' "${fp}"
}

function myguard_nginx_key_ok() {
    local key="${1}" fp=""
    [[ -s "${key}" ]] || return 1
    if ! command -v gpg >/dev/null 2>&1; then
        warning "gpg is not installed; the MyGuard key fingerprint was not checked."
        return 0
    fi
    fp=$(myguard_nginx_key_fingerprint "${key}")
    [[ "${fp}" == "${MYGUARD_NGINX_KEY_FPR}" ]]
}

##
# Install the scoped MyGuard signing key.
##
function ensure_myguard_nginx_key() {
    local root="${LEMPER_APT_ROOT:-/etc/apt}"
    local key="${root}/keyrings/deb.myguard.nl.gpg"
    local tmp=""
    if [[ -s "${key}" ]] && myguard_nginx_key_ok "${key}"; then
        return 0
    fi
    if ! install -d -m 0755 "${root}/keyrings"; then
        mkdir -p "${root}/keyrings" || return 1
    fi
    tmp=$(mktemp "${TMPDIR:-/tmp}/lemper-myguard-key.XXXXXX") || return 1
    if ! curl -fsSL --retry 3 --retry-delay 2 -o "${tmp}" "${MYGUARD_NGINX_KEY_URL}"; then
        rm -f "${tmp}"
        error "Failed to download the MyGuard signing key."
        return 1
    fi
    if ! myguard_nginx_key_ok "${tmp}"; then
        rm -f "${tmp}"
        error "MyGuard signing key fingerprint does not match ${MYGUARD_NGINX_KEY_FPR}."
        return 1
    fi
    mv "${tmp}" "${key}" || return 1
    chmod 0644 "${key}" || true
}

##
# Write the nginx-only MyGuard source and a package-scoped pin.
##
function ensure_myguard_nginx_repo() {
    local root="${LEMPER_APT_ROOT:-/etc/apt}"
    local codename="" line="" list="" pin=""
    codename=$(nginx_release_codename) || {
        error "Unable to detect the distribution codename for the MyGuard nginx repository."
        return 1
    }
    if ! nginx_codename_supported "${codename}"; then
        error "MyGuard nginx packages are not published for '${codename}'."
        return 1
    fi
    ensure_myguard_nginx_key || return 1
    line=$(myguard_nginx_source_line) || return 1
    mkdir -p "${root}/sources.list.d" "${root}/preferences.d" || return 1
    list="${root}/sources.list.d/myguard-nginx-${codename}.list"
    pin="${root}/preferences.d/myguard-nginx-${codename}.pref"
    if [[ ! -f "${list}" ]] || ! grep -qF "https://deb.myguard.nl/apt/nginx/${codename}" "${list}"; then
        printf '%s\n' "${line}" >"${list}" || return 1
        info "Enabled MyGuard nginx repository: ${list}"
    fi
    myguard_nginx_pin_text >"${pin}" || return 1
}

##
# Disable the dead nginx archive, then refresh package lists.
##
function refresh_stack_apt() {
    if ! retire_ondrej_nginx_sources; then
        error "Could not disable the retired Ondřej nginx repository."
        return 1
    fi
    refresh_php_apt_source || return 1
    apt-get update -q
}

# Reuse the installer driver without adding a source on hosts without PHP.
function refresh_php_apt_source() {
    local root
    root=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd) || return 1
    if [[ "$(type -t lemper_load_module)" != function ]]; then
        # shellcheck source=lib/core/loader.sh
        . "$root/core/loader.sh" || return 1
    fi
    lemper_load_module services/apt/repositories || return 1
    if ! lemper_apt_has_source php && [[ -z "$(php_installed_branches)" ]]; then return 0; fi
    lemper_load_module services/php/repository || return 1
    lemper_php_prepare_repository
}

##
# Disable the dead nginx archive, add MyGuard when nginx is packaged, then refresh.
##
function refresh_nginx_apt() {
    if ! retire_ondrej_nginx_sources; then
        error "Could not disable the retired Ondřej nginx repository."
        return 1
    fi
    if nginx_is_package_managed; then
        if ! ensure_myguard_nginx_repo; then
            error "Could not enable the MyGuard nginx repository."
            return 1
        fi
    fi
    refresh_php_apt_source || return 1
    if ! apt-get update -q; then
        error "apt-get update failed."
        return 1
    fi
}
