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
# Fixed upstream releases for CVE-2026-109618 / CVE-2026-109619.
# Keep in sync with https://www.php.net/archive/2026.php
##
function php_fixed_version() {
    case "${1}" in
        8.2) echo "8.2.35" ;;
        8.3) echo "8.3.36" ;;
        8.4) echo "8.4.27" ;;
        8.5) echo "8.5.12" ;;
        *) return 1 ;;
    esac
}

##
# Compare two dotted versions (Debian suffixes/epochs are stripped).
##
function version_ge() {
    local left right
    left=$(printf '%s' "${1}" | sed -E 's/^[0-9]+://; s/-.*$//')
    right=$(printf '%s' "${2}" | sed -E 's/^[0-9]+://; s/-.*$//')

    [[ -z "${left}" || -z "${right}" ]] && return 1

    [[ "$(printf '%s\n%s\n' "${right}" "${left}" | sort -V | head -n 1)" == "${right}" ]]
}

##
# List installed PHP branches (directory scan plus dpkg metadata).
##
function php_installed_branches() {
    {
        if [[ -d "${PHP_ETC_DIR}" ]]; then
            local dir
            for dir in "${PHP_ETC_DIR}"/*/fpm; do
                [[ -d "${dir}" ]] && basename "$(dirname "${dir}")"
            done
        fi

        dpkg-query -W -f='${Package}\n' 'php*-fpm' 2>/dev/null \
            | sed -n 's/^php\([0-9][0-9]*\.[0-9][0-9]*\)-fpm$/\1/p' || true
    } | sort -Vu
}

##
# Print the installed package version for a PHP branch.
##
function php_package_version() {
    local branch="${1}"
    local version=""

    version=$(dpkg-query -W -f='${Version}' "php${branch}-common" 2>/dev/null || true)
    if [[ -z "${version}" ]]; then
        version=$(dpkg-query -W -f='${Version}' "php${branch}-fpm" 2>/dev/null || true)
    fi
    if [[ -z "${version}" ]] && command -v "php${branch}" >/dev/null 2>&1; then
        version=$("php${branch}" -r 'echo PHP_VERSION;' 2>/dev/null || true)
    fi

    printf '%s\n' "${version}"
}

##
# Classify a branch: patched | vulnerable | eol | unknown.
##
function php_branch_state() {
    local branch="${1}"
    local installed="${2}"
    local fixed

    if ! fixed=$(php_fixed_version "${branch}"); then
        echo "eol"
        return 0
    fi

    if [[ -z "${installed}" ]]; then
        echo "unknown"
        return 0
    fi

    if version_ge "${installed}" "${fixed}"; then
        echo "patched"
    else
        echo "vulnerable"
    fi
}

##
# List FPM pool configuration files for a branch.
##
function php_pool_files() {
    local branch="${1}"
    local dir="${PHP_ETC_DIR}/${branch}/fpm/pool.d"

    [[ -d "${dir}" ]] || return 0
    find "${dir}" -maxdepth 1 -type f -name '*.conf' | sort
}

##
# Portable in-place extended-regex replacement (GNU and BSD sed).
##
function sed_inplace_ere() {
    local file="${1}"
    local expr="${2}"
    local tmp

    tmp=$(mktemp "${file}.XXXXXX") || return 1
    cp -p "${file}" "${tmp}" || {
        rm -f "${tmp}"
        return 1
    }

    if sed -E "${expr}" "${file}" >"${tmp}"; then
        mv "${tmp}" "${file}"
    else
        rm -f "${tmp}"
        return 1
    fi
}

##
# Set an admin-locked php_value and upgrade any existing php_value override.
##
function pool_set_admin_value() {
    local file="${1}"
    local key="${2}"
    local value="${3}"
    local key_re="${key//./\\.}"
    local directive="php_admin_value[${key}]"

    if grep -qE "^[[:space:]]*php_(admin_)?value\[${key_re}\][[:space:]]*=" "${file}"; then
        sed_inplace_ere "${file}" \
            "s|^[[:space:]]*php_(admin_)?value\[${key_re}\][[:space:]]*=.*|${directive} = ${value}|"
    else
        printf '%s = %s\n' "${directive}" "${value}" >>"${file}"
    fi
}

##
# Set an admin-locked php_flag and upgrade any existing php_flag override.
##
function pool_set_admin_flag() {
    local file="${1}"
    local key="${2}"
    local value="${3}"
    local key_re="${key//./\\.}"
    local directive="php_admin_flag[${key}]"

    if grep -qE "^[[:space:]]*php_(admin_)?flag\[${key_re}\][[:space:]]*=" "${file}"; then
        sed_inplace_ere "${file}" \
            "s|^[[:space:]]*php_(admin_)?flag\[${key_re}\][[:space:]]*=.*|${directive} = ${value}|"
    else
        printf '%s = %s\n' "${directive}" "${value}" >>"${file}"
    fi
}

##
# Check whether a pool already carries the PHP2Shell controls.
##
function php_mitigation_present() {
    local file="${1}"

    grep -qE '^[[:space:]]*php_admin_value\[memory_limit\][[:space:]]*=[[:space:]]*-1' "${file}" \
        && grep -qE '^[[:space:]]*php_admin_flag\[session\.upload_progress\.enabled\][[:space:]]*=[[:space:]]*0' "${file}"
}

##
# Apply the controls to one pool file (no service reload).
##
function php_mitigate_pool_file() {
    local file="${1}"
    local branch="${2}"

    if ! grep -q 'LEMPer PHP2Shell mitigation' "${file}"; then
        printf '\n; LEMPer PHP2Shell mitigation (%s)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"${file}"
    fi

    pool_set_admin_value "${file}" "memory_limit" "${PHP2SHELL_MEMORY_LIMIT}"
    pool_set_admin_value "${file}" "post_max_size" "${PHP2SHELL_POST_MAX}"
    pool_set_admin_flag "${file}" "session.upload_progress.enabled" "0"

    if [[ "${branch}" == "8.5" ]]; then
        pool_set_admin_flag "${file}" "fatal_error_backtraces" "0"
    fi
}

##
# Count pools on a branch, optionally only those already mitigated.
##
function php_pool_count() {
    local branch="${1}"
    local only_mitigated="${2:-false}"
    local file count=0

    while IFS= read -r file; do
        [[ -f "${file}" ]] || continue
        if [[ "${only_mitigated}" == "true" ]]; then
            php_mitigation_present "${file}" || continue
        fi
        count=$((count + 1))
    done < <(php_pool_files "${branch}")

    echo "${count}"
}

##
# Reload PHP-FPM for a branch after a package or pool change.
##
function php_reload_branch() {
    local branch="${1}"

    if ! command -v systemctl >/dev/null 2>&1; then
        return 0
    fi

    if systemctl list-unit-files "php${branch}-fpm.service" 2>/dev/null | grep -q "php${branch}-fpm.service"; then
        if systemctl try-reload-or-restart "php${branch}-fpm" 2>/dev/null; then
            success "php${branch}-fpm reloaded."
        else
            warning "Could not reload php${branch}-fpm; restart it manually."
        fi
    fi
}

##
# Decide what to do with one installed PHP package during an upgrade.
# Prints upgrade, remove, or skip.
# phpX.Y-json used to be a real transitional package. Current Ondřej builds
# publish it only as a virtual package provided by the SAPI packages, and
# passing that name to apt-get install aborts the whole branch upgrade.
##
function php_upgrade_action() {
    local pkg="${1}"
    local candidate="${2}"

    if [[ -n "${candidate}" && "${candidate}" != "(none)" ]]; then
        printf '%s\n' "upgrade"
        return 0
    fi
    if [[ "${pkg}" =~ ^php[0-9]+\.[0-9]+-json$ ]]; then
        printf '%s\n' "remove"
        return 0
    fi
    printf '%s\n' "skip"
}

##
# Candidate version, or nothing when apt cannot install the package.
##
function php_apt_candidate() {
    local cand=""
    cand=$(apt-cache policy "${1}" 2>/dev/null | awk '/^[[:space:]]*Candidate:/ {print $2; exit}' || true)
    printf '%s\n' "${cand}"
}

##
# Upgrade a patched PHP branch and verify the running package version.
##
function php_patch_branch() {
    local branch="${1}"
    local fixed="${2}"
    local pkgs=()
    local remove_pkgs=()
    local pkg action installed

    while IFS= read -r pkg; do
        [[ -n "${pkg}" ]] || continue
        action=$(php_upgrade_action "${pkg}" "$(php_apt_candidate "${pkg}")")
        case "${action}" in
            upgrade)
                pkgs+=("${pkg}")
                ;;
            remove)
                info "Removing retired package ${pkg}; JSON is included in the PHP ${branch} SAPI packages."
                remove_pkgs+=("${pkg}")
                ;;
            *)
                warning "Skipping ${pkg}; apt has no installation candidate for it."
                ;;
        esac
    done < <(dpkg-query -W -f='${Package}\n' "php${branch}-*" 2>/dev/null || true)

    if [[ "${#pkgs[@]}" -eq 0 ]]; then
        for pkg in "php${branch}-fpm" "php${branch}-cli" "php${branch}-common"; do
            action=$(php_upgrade_action "${pkg}" "$(php_apt_candidate "${pkg}")")
            if [[ "${action}" == "upgrade" ]]; then
                pkgs+=("${pkg}")
            fi
        done
    fi

    if [[ "${#pkgs[@]}" -eq 0 ]]; then
        error "No upgradable PHP ${branch} packages found."
        return 1
    fi

    if [[ "${#remove_pkgs[@]}" -gt 0 ]]; then
        if ! DEBIAN_FRONTEND=noninteractive apt-get remove -y -q "${remove_pkgs[@]}"; then
            warning "Could not remove retired package(s): ${remove_pkgs[*]}. The PHP ${branch} upgrade will continue."
        fi
    fi

    info "Upgrading PHP ${branch} packages to >= ${fixed}..."
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -q --only-upgrade "${pkgs[@]}"; then
        error "Failed to upgrade PHP ${branch} packages."
        return 1
    fi

    installed=$(php_package_version "${branch}")
    if version_ge "${installed}" "${fixed}"; then
        success "PHP ${branch} is patched (${installed})."
        php_reload_branch "${branch}"
        return 0
    fi

    error "PHP ${branch} is still ${installed:-unknown} (< ${fixed}); the configured repository may not carry the patch yet."
    return 1
}

##
# Apply compensating controls to every pool on an EOL branch.
##
function php_mitigate_branch() {
    local branch="${1}"
    local stamp backup_dir pool count=0

    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    backup_dir="${LEMPER_BACKUP_DIR}/php2shell-${stamp}/${branch}"

    if ! mkdir -p "${backup_dir}"; then
        error "Cannot create backup directory ${backup_dir}."
        return 1
    fi
    chmod 0700 "${LEMPER_BACKUP_DIR}" "${backup_dir}" 2>/dev/null || true

    while IFS= read -r pool; do
        [[ -f "${pool}" ]] || continue
        cp -a "${pool}" "${backup_dir}/$(basename "${pool}")" || {
            error "Cannot back up ${pool}; refusing to modify pools."
            return 1
        }
        php_mitigate_pool_file "${pool}" "${branch}"
        count=$((count + 1))
    done < <(php_pool_files "${branch}")

    if [[ "${count}" -eq 0 ]]; then
        info "No FPM pools found for PHP ${branch}."
        return 0
    fi

    if [[ "${PHP2SHELL_MEMORY_LIMIT}" != "-1" ]]; then
        warning "memory_limit=${PHP2SHELL_MEMORY_LIMIT} keeps the OOM path reachable; this mitigation is incomplete."
    fi

    success "Applied PHP2Shell controls to ${count} PHP ${branch} pool(s)."
    info "Pool backups: ${backup_dir}"
    php_reload_branch "${branch}"
}

##
# True when the branch has a vendor fix for PHP2Shell.
##
function php_branch_is_supported() {
    php_fixed_version "${1}" >/dev/null
}
