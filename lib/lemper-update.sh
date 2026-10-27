#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Security & Stack Updater                                   |
# +-------------------------------------------------------------------------+
# | Patches PHP2Shell (CVE-2026-109618 / CVE-2026-109619) and keeps the     |
# | rest of the stack current. Supported branches are upgraded from apt.    |
# | --migrate-to=VERSION moves EOL vhosts onto that PHP and creates any     |
# | missing FPM pool. Without it, EOL pools get compensating controls.      |
# |                                                                         |
# | Invoked as: lemper-cli update <check|php|nginx|mariadb|lemper|all>      |
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

CMD_PARENT="${PROG_NAME}"
CMD_NAME="update"

# Make sure only root can access and not direct access.
if [[ "$(type -t requires_root)" != "function" ]]; then
    echo "Direct access to this script is not permitted."
    exit 1
fi

PHP_ETC_DIR="${PHP_ETC_DIR:-/etc/php}"
LEMPER_BACKUP_DIR="${LEMPER_BACKUP_DIR:-/etc/lemper/backups}"
LEMPER_UPDATE_SOURCE_FILE="${LEMPER_UPDATE_SOURCE_FILE:-/etc/lemper/update-source}"
LEMPER_LOG_DIR="${LEMPER_LOG_DIR:-/var/log/lemper}"

# Compensating controls for branches without a vendor patch.
PHP2SHELL_MEMORY_LIMIT="${PHP2SHELL_MEMORY_LIMIT:--1}"
PHP2SHELL_POST_MAX="${PHP2SHELL_POST_MAX:-32M}"

UPDATE_ASSUME_YES="${UPDATE_ASSUME_YES:-false}"
UPDATE_SOURCE_DIR=""
UPDATE_LOG=""
# Set only by --migrate-to / --force=VERSION. An inherited environment value
# must not move production vhosts during a normal update.
PHP_MIGRATE_TO=""
UPDATE_REQUESTED_SUBCOMMAND=""

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

        dpkg-query -W -f='${Package}\n' 'php*-fpm' 2>/dev/null |
            sed -n 's/^php\([0-9][0-9]*\.[0-9][0-9]*\)-fpm$/\1/p' || true
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
    cp -p "${file}" "${tmp}" || { rm -f "${tmp}"; return 1; }

    if sed -E "${expr}" "${file}" > "${tmp}"; then
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
        printf '%s = %s\n' "${directive}" "${value}" >> "${file}"
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
        printf '%s = %s\n' "${directive}" "${value}" >> "${file}"
    fi
}

##
# Check whether a pool already carries the PHP2Shell controls.
##
function php_mitigation_present() {
    local file="${1}"

    grep -qE '^[[:space:]]*php_admin_value\[memory_limit\][[:space:]]*=[[:space:]]*-1' "${file}" &&
        grep -qE '^[[:space:]]*php_admin_flag\[session\.upload_progress\.enabled\][[:space:]]*=[[:space:]]*0' "${file}"
}

##
# Apply the controls to one pool file (no service reload).
##
function php_mitigate_pool_file() {
    local file="${1}"
    local branch="${2}"

    if ! grep -q 'LEMPer PHP2Shell mitigation' "${file}"; then
        printf '\n; LEMPer PHP2Shell mitigation (%s)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${file}"
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

##
# branch<TAB>pool from a fastcgi_pass socket. The bare www socket has no user.
##
function php_parse_fpm_socket() {
    local line="${1}" branch="" pool=""

    [[ "${line}" =~ php([0-9]+\.[0-9]+)-fpm(\.([A-Za-z0-9_-]+))?\.sock ]] || return 1
    branch="${BASH_REMATCH[1]}"
    pool="${BASH_REMATCH[3]}"
    [[ -z "${pool}" ]] && pool="www"
    printf '%s\t%s\n' "${branch}" "${pool}"
}

##
# Rewrite EOL PHP-FPM sockets to the destination version. Supported sockets stay.
##
function php_migrate_fastcgi_line() {
    local line="${1}"
    local target="${2}"
    local rest="${1}"
    local parsed="" branch="" guard=0
    local from_token="" to_token=""

    if [[ "${line}" =~ ^[[:space:]]*# ]]; then
        printf '%s\n' "${line}"
        return 0
    fi

    while parsed=$(php_parse_fpm_socket "${rest}"); do
        guard=$((guard + 1))
        [[ "${guard}" -gt 8 ]] && break
        branch="${parsed%%$'\t'*}"
        from_token="php${branch}-fpm"
        to_token="php${target}-fpm"
        if ! php_branch_is_supported "${branch}"; then
            line="${line//"${from_token}"/${to_token}}"
        fi
        rest="${rest#*"${from_token}"}"
    done
    printf '%s\n' "${line}"
}

##
# branch<TAB>pool for every EOL socket on one line.
##
function php_eol_socket_pairs() {
    local rest="${1}" parsed="" branch="" pool="" guard=0
    local from_token=""

    while parsed=$(php_parse_fpm_socket "${rest}"); do
        guard=$((guard + 1))
        [[ "${guard}" -gt 8 ]] && break
        branch="${parsed%%$'\t'*}"
        pool="${parsed#*$'\t'}"
        from_token="php${branch}-fpm"
        if ! php_branch_is_supported "${branch}"; then
            printf '%s\t%s\n' "${branch}" "${pool}"
        fi
        rest="${rest#*"${from_token}"}"
    done
}

##
# Version from `set $php_version "X.Y"`, or failure when the line has none.
##
function php_assigned_php_version() {
    local line="${1}"

    if [[ "${line}" =~ set[[:space:]]+\$php_version[[:space:]]+\"([0-9]+\.[0-9]+)\" ]] || \
        [[ "${line}" =~ set[[:space:]]+\$php_version[[:space:]]+\'([0-9]+\.[0-9]+)\' ]] || \
        [[ "${line}" =~ set[[:space:]]+\$php_version[[:space:]]+([0-9]+\.[0-9]+)([^0-9.]|$) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

##
# Point an EOL `set $php_version` line at the destination release.
##
function php_migrate_version_assignment() {
    local line="${1}" target="${2}" branch=""

    if [[ "${line}" =~ ^[[:space:]]*# ]]; then
        printf '%s\n' "${line}"
        return 0
    fi

    branch=$(php_assigned_php_version "${line}") || {
        printf '%s\n' "${line}"
        return 0
    }
    if php_branch_is_supported "${branch}"; then
        printf '%s\n' "${line}"
        return 0
    fi
    if [[ "${line}" == *"\"${branch}\""* ]]; then
        line="${line/\"${branch}\"/\"${target}\"}"
    elif [[ "${line}" == *"'${branch}'"* ]]; then
        line="${line/\'${branch}\'/\'${target}\'}"
    else
        line="${line/${branch}/${target}}"
    fi
    printf '%s\n' "${line}"
}

##
# Absolute path of a vhost file. Symlinks collapse to the target file.
##
function php_migrate_realpath() {
    local path="${1}"

    if command -v realpath >/dev/null 2>&1; then
        realpath "${path}" 2>/dev/null && return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${path}"
        return 0
    fi
    if [[ -L "${path}" ]]; then
        return 1
    fi
    printf '%s\n' "${path}"
}

##
# Put backed-up vhosts back after a failed migration.
##
function php_migrate_restore_manifest() {
    local manifest="${1}" backup="" vhost=""

    [[ -f "${manifest}" ]] || return 0
    while IFS=$'\t' read -r backup vhost || [[ -n "${backup}" ]]; do
        [[ -z "${backup}" ]] && continue
        [[ -f "${backup}" && -n "${vhost}" ]] || continue
        cp -a "${backup}" "${vhost}" || true
    done < "${manifest}"
}

##
# Rewrite phpX.Y path and extension-suffix tokens from one branch to another.
##
function php_rewrite_pool_text() {
    local from="${1}" to="${2}"
    local from_compact="${from//./}" to_compact="${to//./}"
    sed "s/php${from}/php${to}/g; s/\\.php${from_compact}/.php${to_compact}/g"
}

##
# Minimal pool used when the EOL branch has no pool file for this user.
##
function php_minimal_pool_text() {
    local pool="${1}" version="${2}"
    local user="${pool}" group="${pool}" home="/home/${pool}" listen_name=".${pool}"

    if [[ "${pool}" == "www" ]]; then
        user="www-data"
        group="www-data"
        home="/usr/share/nginx/html"
        listen_name=""
    fi

    cat <<EOF
[${pool}]
user = ${user}
group = ${group}
listen = /run/php/php${version}-fpm${listen_name}.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.process_idle_timeout = 30s
pm.max_requests = 500
request_terminate_timeout = 300s
chdir = ${home}
clear_env = yes
security.limit_extensions = .php .php${version//./}
php_admin_flag[log_errors] = on
php_admin_flag[expose_php] = off
php_admin_flag[display_errors] = off
php_admin_flag[display_startup_errors] = off
php_flag[cgi.fix_pathinfo] = off
php_admin_value[error_log] = ${home}/logs/php/php${version}-fpm_error.log
php_admin_value[open_basedir] = ${home}:/var/lib/php/lemper/${pool}
php_admin_value[sys_temp_dir] = /var/lib/php/lemper/${pool}/tmp
php_admin_value[upload_tmp_dir] = /var/lib/php/lemper/${pool}/tmp
php_admin_value[session.save_path] = /var/lib/php/lemper/${pool}/sessions
php_admin_value[session.use_strict_mode] = 1
php_admin_value[session.cookie_httponly] = 1
php_admin_value[session.cookie_samesite] = Lax
EOF
}

##
# Private temp and session directories for a migrated pool.
##
function php_migrate_prepare_pool_dirs() {
    local pool="${1}"
    local base="${LEMPER_PHP_STATE_DIR:-/var/lib/php/lemper}/${pool}"
    local owner="${pool}"

    mkdir -p "${base}/tmp" "${base}/sessions" "${base}/wsdlcache" "${base}/opcache" || return 1
    chmod 700 "${base}" "${base}/tmp" "${base}/sessions" "${base}/wsdlcache" "${base}/opcache" 2>/dev/null || true
    if [[ "$(id -u)" -eq 0 ]]; then
        [[ "${pool}" == "www" ]] && owner="www-data"
        if id "${owner}" >/dev/null 2>&1; then
            chown -R "${owner}:${owner}" "${base}" 2>/dev/null || true
        fi
    fi
}

##
# Create the destination pool from the EOL pool, or from a minimal template.
##
function php_ensure_migrated_pool() {
    local pool="${1}" from="${2}" to="${3}"
    local dest="${PHP_ETC_DIR}/${to}/fpm/pool.d/${pool}.conf"
    local src="${PHP_ETC_DIR}/${from}/fpm/pool.d/${pool}.conf"

    if [[ -f "${dest}" ]]; then
        info "PHP ${to} pool ${pool} already exists."
        return 0
    fi
    mkdir -p "${PHP_ETC_DIR}/${to}/fpm/pool.d" || return 1
    if [[ -f "${src}" ]]; then
        php_rewrite_pool_text "${from}" "${to}" < "${src}" > "${dest}" || return 1
        info "Created PHP ${to} pool ${pool} from the PHP ${from} pool."
    else
        php_minimal_pool_text "${pool}" "${to}" > "${dest}" || return 1
        info "Created a new PHP ${to} pool for ${pool}."
    fi
    chmod 0644 "${dest}" 2>/dev/null || true
    php_migrate_prepare_pool_dirs "${pool}" || return 1
    php_migrate_prepare_log_dir "${pool}"
}

##
# Best-effort PHP log directory named by the pool file.
##
function php_migrate_prepare_log_dir() {
    local pool="${1}"
    local log_dir="/home/${pool}/logs/php"
    local owner="${pool}"

    if [[ "${pool}" == "www" ]]; then
        log_dir="/usr/share/nginx/html/logs/php"
        owner="www-data"
    elif [[ "$(id -u)" -ne 0 && ! -d "/home/${pool}" ]]; then
        return 0
    fi
    mkdir -p "${log_dir}" 2>/dev/null || true
    chmod 750 "${log_dir}" 2>/dev/null || true
    if [[ "$(id -u)" -eq 0 ]] && id "${owner}" >/dev/null 2>&1; then
        chown "${owner}:${owner}" "${log_dir}" 2>/dev/null || true
    fi
}

##
# Point EOL fastcgi_pass sockets at the destination PHP and create missing pools.
# Existing destination pools are kept. Old pools and packages are left in place.
##
function php_migrate_eol_sites() {
    local target="${1}"
    local sites="${LEMPER_NGINX_SITES_DIR:-/etc/nginx/sites-available}"
    local enabled="${LEMPER_NGINX_SITES_ENABLED:-$(dirname "${sites}")/sites-enabled}"
    local stamp="" backup_dir="" manifest="" vhost="" tmp="" line="" new_line=""
    local resolved="" entry="" dir="" branch="" pool="" assigned="" suffix=""
    local backup_file="" seen_pools=" " seen_paths="" vhost_changed=0
    local -a vhosts=()

    if ! php_branch_is_supported "${target}"; then
        error "PHP ${target} is not a supported migration target. Choose 8.2, 8.3, 8.4, or 8.5."
        return 1
    fi
    if [[ ! -d "${PHP_ETC_DIR}/${target}/fpm" ]]; then
        error "PHP ${target} is not installed. Install it, then re-run with --migrate-to=${target}."
        return 1
    fi

    for dir in "${sites}" "${enabled}"; do
        [[ -d "${dir}" ]] || continue
        for entry in "${dir}"/*.conf; do
            [[ -e "${entry}" ]] || continue
            resolved=$(php_migrate_realpath "${entry}") || continue
            [[ -f "${resolved}" ]] || continue
            if printf '%s\n' "${seen_paths}" | grep -Fxq "${resolved}"; then
                continue
            fi
            seen_paths="${seen_paths}"$'\n'"${resolved}"
            vhosts+=("${resolved}")
        done
    done

    if [[ "${#vhosts[@]}" -eq 0 ]]; then
        info "No Nginx vhosts found to migrate."
        return 0
    fi

    for vhost in "${vhosts[@]}"; do
        tmp=$(mktemp "${TMPDIR:-/tmp}/lemper-vhost.XXXXXX") || return 1
        : > "${tmp}"
        vhost_changed=0
        while IFS= read -r line || [[ -n "${line}" ]]; do
            new_line=$(php_migrate_fastcgi_line "${line}" "${target}")
            new_line=$(php_migrate_version_assignment "${new_line}" "${target}")
            if [[ "${new_line}" != "${line}" ]]; then
                vhost_changed=1
                while IFS=$'\t' read -r branch pool; do
                    [[ -z "${branch}" || -z "${pool}" ]] && continue
                    if [[ "${seen_pools}" != *" ${branch}:${pool} "* ]]; then
                        seen_pools+="${branch}:${pool} "
                        if ! php_ensure_migrated_pool "${pool}" "${branch}" "${target}"; then
                            rm -f "${tmp}"
                            php_migrate_restore_manifest "${manifest}"
                            return 1
                        fi
                    fi
                done <<< "$(php_eol_socket_pairs "${line}")"
                assigned=$(php_assigned_php_version "${line}" || true)
                if [[ -n "${assigned}" ]] && ! php_branch_is_supported "${assigned}"; then
                    if [[ "${seen_pools}" != *" ${assigned}:www "* ]]; then
                        seen_pools+="${assigned}:www "
                        if ! php_ensure_migrated_pool "www" "${assigned}" "${target}"; then
                            rm -f "${tmp}"
                            php_migrate_restore_manifest "${manifest}"
                            return 1
                        fi
                    fi
                fi
            fi
            printf '%s\n' "${new_line}" >> "${tmp}"
        done < "${vhost}"
        if [[ "${vhost_changed}" -eq 0 ]]; then
            rm -f "${tmp}"
            continue
        fi
        if [[ -z "${backup_dir}" ]]; then
            stamp=$(date -u +%Y%m%dT%H%M%SZ)
            backup_dir="${LEMPER_BACKUP_DIR}/php-migrate-${stamp}"
            mkdir -p "${backup_dir}" || {
                rm -f "${tmp}"
                return 1
            }
            chmod 0700 "${backup_dir}" 2>/dev/null || true
            manifest="${backup_dir}/manifest.tsv"
            : > "${manifest}"
            chmod 0600 "${manifest}" 2>/dev/null || true
        fi
        suffix=$(cksum "${vhost}" 2>/dev/null | awk '{print $1}')
        [[ -z "${suffix}" ]] && suffix="${RANDOM}"
        backup_file="${backup_dir}/$(basename "${vhost}").${suffix}"
        if ! cp -a "${vhost}" "${backup_file}"; then
            rm -f "${tmp}"
            php_migrate_restore_manifest "${manifest}"
            return 1
        fi
        if ! cat "${tmp}" > "${vhost}"; then
            rm -f "${tmp}"
            php_migrate_restore_manifest "${manifest}"
            return 1
        fi
        rm -f "${tmp}"
        printf '%s\t%s\n' "${backup_file}" "${vhost}" >> "${manifest}"
        info "Migrated EOL PHP handlers in ${vhost} to PHP ${target}."
    done

    if [[ -z "${backup_dir}" ]]; then
        info "No EOL PHP sockets found in Nginx vhosts."
        return 0
    fi

    # Unit tests point the sites directory at a fixture. Only a real
    # sites-available tree is allowed to invoke the local nginx binary.
    if [[ "${sites}" == "/etc/nginx/sites-available" ]] && command -v nginx >/dev/null 2>&1; then
        if ! nginx -t; then
            error "nginx configuration test failed; restoring vhosts."
            php_migrate_restore_manifest "${manifest}"
            return 1
        fi
        systemctl try-reload-or-restart "php${target}-fpm" 2>/dev/null || \
            warning "PHP ${target} FPM pool files were written; reload php${target}-fpm manually."
        if systemctl reload nginx 2>/dev/null; then
            success "Nginx reloaded with PHP ${target} handlers."
        else
            warning "Vhosts now use PHP ${target}; reload Nginx manually."
        fi
    fi

    success "EOL vhosts now use PHP ${target}. Previous vhosts: ${backup_dir}."
    warning "The old PHP packages and pools are still installed. Stop those FPM services after the sites answer on PHP ${target}."
}

##
# Patch supported PHP branches and mitigate or migrate EOL branches.
##
function update_php() {
    local branches branch installed state fixed rc=0
    local -a eol_branches=()
    local migrate=0

    if [[ -n "${PHP_MIGRATE_TO:-}" ]]; then
        if [[ ! "${PHP_MIGRATE_TO}" =~ ^[0-9]+\.[0-9]+$ ]] || ! php_branch_is_supported "${PHP_MIGRATE_TO}"; then
            error "PHP ${PHP_MIGRATE_TO} is not a supported migration target. Choose 8.2, 8.3, 8.4, or 8.5."
            return 1
        fi
        migrate=1
    fi

    branches=$(php_installed_branches)
    if [[ -z "${branches}" ]]; then
        if [[ "${migrate}" -eq 1 ]]; then
            php_migrate_eol_sites "${PHP_MIGRATE_TO}" || return 1
            return 0
        fi
        info "No PHP installation detected."
        return 0
    fi

    while IFS= read -r branch; do
        [[ -z "${branch}" ]] && continue
        installed=$(php_package_version "${branch}")
        state=$(php_branch_state "${branch}" "${installed}")

        case "${state}" in
            patched)
                success "PHP ${branch} (${installed}) already includes the fix."
                ;;
            vulnerable)
                fixed=$(php_fixed_version "${branch}")
                warning "PHP ${branch} (${installed}) is vulnerable; fixed release: ${fixed}."
                php_patch_branch "${branch}" "${fixed}" || rc=1
                ;;
            eol)
                eol_branches+=("${branch}")
                if [[ "${migrate}" -eq 0 ]]; then
                    warning "PHP ${branch} is EOL and has no vendor patch for PHP2Shell."
                    php_mitigate_branch "${branch}" || rc=1
                    warning "PHP ${branch} remains exploitable. Re-run 'update php --migrate-to=8.3' (or 8.2, 8.4, 8.5) to move its vhosts."
                    rc=1
                else
                    warning "PHP ${branch} is EOL. Vhosts that use it will move to PHP ${PHP_MIGRATE_TO}."
                fi
                ;;
            *)
                warning "Unable to determine the PHP ${branch} version."
                rc=1
                ;;
        esac
    done <<< "${branches}"

    if [[ "${migrate}" -eq 1 ]]; then
        if php_migrate_eol_sites "${PHP_MIGRATE_TO}"; then
            for branch in "${eol_branches[@]}"; do
                [[ -z "${branch}" ]] && continue
                php_mitigate_branch "${branch}" || rc=1
                warning "PHP ${branch} is still installed. Stop php${branch}-fpm after the migrated sites are checked."
            done
        else
            rc=1
        fi
    fi

    return "${rc}"
}

# Apt configuration root. Tests point this at a fixture directory.
LEMPER_APT_ROOT="${LEMPER_APT_ROOT:-/etc/apt}"

# MyGuard nginx-only repository. The signing key is published by Thijs Eilander.
MYGUARD_NGINX_KEY_URL="${MYGUARD_NGINX_KEY_URL:-https://deb.myguard.nl/deb.myguard.nl.gpg}"
MYGUARD_NGINX_KEY_FPR="D18B8E5ADF7D55CE2A00D58167F9C3D8456D7F62"

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
    done < "${1}"
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
    done < "${1}"
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
    done <<< "${1}"
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
            printf '# lemper-retired-ondrej-nginx: %s\n' "${line}" >> "${tmp}" || {
                rm -f "${tmp}"
                return 1
            }
            changed=1
        else
            printf '%s\n' "${line}" >> "${tmp}" || {
                rm -f "${tmp}"
                return 1
            }
        fi
    done < "${src}"
    if [[ "${changed}" -eq 0 ]]; then
        rm -f "${tmp}"
        return 0
    fi
    if ! cat "${tmp}" > "${src}"; then
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
    done < "${src}"
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
    printf '%s' "${kept}" > "${tmp}" || {
        rm -f "${tmp}"
        return 1
    }
    if ! cat "${tmp}" > "${src}"; then
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
        printf '%s\n' "${line}" > "${list}" || return 1
        info "Enabled MyGuard nginx repository: ${list}"
    fi
    myguard_nginx_pin_text > "${pin}" || return 1
}

##
# Disable the dead nginx archive, then refresh package lists.
##
function refresh_stack_apt() {
    if ! retire_ondrej_nginx_sources; then
        error "Could not disable the retired Ondřej nginx repository."
        return 1
    fi
    apt-get update -q
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
    if ! apt-get update -q; then
        error "apt-get update failed."
        return 1
    fi
}

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

##
# Upgrade MariaDB packages and restart only when the version changed.
##
function update_mariadb() {
    local before after pkgs=() pkg before_branch after_branch

    if ! dpkg -s mariadb-server >/dev/null 2>&1; then
        info "MariaDB server is not installed."
        return 0
    fi

    before=$(dpkg-query -W -f='${Version}' mariadb-server)

    while IFS= read -r pkg; do
        [[ -n "${pkg}" ]] && pkgs+=("${pkg}")
    done < <(dpkg-query -W -f='${Package}\n' 'mariadb-server*' 'mariadb-client*' 'mariadb-common' 2>/dev/null || true)

    [[ "${#pkgs[@]}" -eq 0 ]] && pkgs=("mariadb-server" "mariadb-client" "mariadb-common")

    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -q --only-upgrade "${pkgs[@]}"; then
        error "Failed to upgrade MariaDB packages."
        return 1
    fi

    after=$(dpkg-query -W -f='${Version}' mariadb-server)
    if [[ "${before}" == "${after}" ]]; then
        info "MariaDB is already current (${after})."
        return 0
    fi

    success "MariaDB upgraded: ${before} -> ${after}."
    if ! systemctl try-restart mariadb 2>/dev/null; then
        error "MariaDB upgraded but could not be restarted."
        return 1
    fi
    success "MariaDB restarted."

    before_branch=$(printf '%s' "${before#*:}" | awk -F. '{print $1"."$2}')
    after_branch=$(printf '%s' "${after#*:}" | awk -F. '{print $1"."$2}')
    if [[ "${before_branch}" != "${after_branch}" ]]; then
        warning "MariaDB branch changed (${before_branch} -> ${after_branch}); run 'mariadb-upgrade' and review the upgrade notes."
    fi
}

##
# Resolve the LEMPer source checkout used to refresh CLI/plugins.
##
function update_resolve_source() {
    if [[ -n "${UPDATE_SOURCE_DIR}" ]]; then
        printf '%s\n' "${UPDATE_SOURCE_DIR}"
        return 0
    fi

    if [[ -f "${LEMPER_UPDATE_SOURCE_FILE}" ]]; then
        head -n 1 "${LEMPER_UPDATE_SOURCE_FILE}"
        return 0
    fi

    if [[ -n "${LEMPER_SRC_DIR:-}" ]]; then
        printf '%s\n' "${LEMPER_SRC_DIR}"
        return 0
    fi

    return 1
}

##
# True when a config file has the openssl enc header.
##
function tools_config_is_encrypted() {
    local file="${1}"
    [[ -f "${file}" ]] || return 1
    head -c 10 "${file}" | grep -qE '^(U2FsdGVkX1|Salted__)'
}

##
# Decrypt lemper.conf into dest. The key file is preferred.
##
function tools_decrypt_config() {
    local src="${1}"
    local dest="${2}"
    local pw=""

    if [[ -f /etc/lemper/.config_key ]]; then
        pw=$(tr -d '\n' < /etc/lemper/.config_key)
    elif [[ -n "${LEMPER_PASSWORD:-}" ]]; then
        pw="${LEMPER_PASSWORD}"
    else
        return 1
    fi

    openssl enc -aes-256-cbc -a -d -salt -md sha256 -pbkdf2 \
        -k "${pw}" -in "${src}" -out "${dest}" 2>/dev/null
}

##
# Pick the dotenv used to reinstall administration tools.
# Prints the path. Sets LEMPER_TOOLS_PRESERVE_ADMIN_CONFIG=true when the
# only available file is the sample .env.dist.
##
function resolve_tools_env() {
    local src="${1}"
    local conf="/etc/lemper/lemper.conf"
    local tmp

    LEMPER_TOOLS_PRESERVE_ADMIN_CONFIG=false

    if [[ -f "${src}/.env" ]]; then
        printf '%s\n' "${src}/.env"
        return 0
    fi

    if [[ -f "${conf}" ]]; then
        tmp=$(mktemp "${TMPDIR:-/tmp}/lemper-tools-env.XXXXXX") || return 1
        chmod 0600 "${tmp}" || true
        if tools_config_is_encrypted "${conf}"; then
            if tools_decrypt_config "${conf}" "${tmp}"; then
                printf '%s\n' "${tmp}"
                return 0
            fi
            rm -f "${tmp}"
            warning "Could not decrypt ${conf}; falling back to .env.dist."
        else
            cp "${conf}" "${tmp}" || { rm -f "${tmp}"; return 1; }
            printf '%s\n' "${tmp}"
            return 0
        fi
    fi

    if [[ -f "${src}/.env.dist" ]]; then
        LEMPER_TOOLS_PRESERVE_ADMIN_CONFIG=true
        printf '%s\n' "${src}/.env.dist"
        return 0
    fi

    error "No .env, ${conf}, or .env.dist is available for the tools reinstall."
    return 1
}

##
# Re-run scripts/install_tools.sh from a checkout. DRYRUN is forced off so
# the CLI, plugins, Adminer, file manager, and PHP admin panels are replaced.
##
function reinstall_admin_tools() {
    local src="${1}"
    local envfile=""
    local tools_rc=0

    [[ -f "${src}/scripts/install_tools.sh" && -f "${src}/scripts/utils.sh" ]] || {
        error "Source at ${src} has no scripts/install_tools.sh."
        return 1
    }

    envfile=$(resolve_tools_env "${src}") || return 1

    info "Reinstalling LEMPer CLI, plugins, and web administration tools from ${src}..."
    DRYRUN=false \
        LEMPER_ENV_FILE="${envfile}" \
        LEMPER_TOOLS_PRESERVE_ADMIN_CONFIG="${LEMPER_TOOLS_PRESERVE_ADMIN_CONFIG}" \
        bash -c '
            tools="$1"
            base=$(cd "$(dirname "${tools}")/.." && pwd) || exit 1
            cd "${base}" || exit 1
            export BASE_DIR="${base}"
            # shellcheck source=scripts/utils.sh
            . "${base}/scripts/utils.sh"
            DRYRUN=false
            shift
            # shellcheck source=scripts/install_tools.sh
            . "${tools}"
        ' _ "${src}/scripts/install_tools.sh" || tools_rc=$?

    if [[ "${envfile}" != "${src}/.env" && "${envfile}" != "${src}/.env.dist" ]]; then
        rm -f "${envfile}"
    fi

    return "${tools_rc}"
}

##
# Refresh the CLI and CLI plugins from a source checkout.
##
function update_lemper_tooling() {
    local src dest name target

    if ! src=$(update_resolve_source); then
        warning "No LEMPer source checkout recorded; skipping CLI/plugin refresh."
        warning "Run update.sh from a checkout to enable future tooling updates."
        return 0
    fi

    if [[ ! -f "${src}/bin/lemper-cli.sh" || ! -f "${src}/lib/lemper-update.sh" ]]; then
        error "Source at ${src} is not a LEMPer checkout."
        return 1
    fi

    dest="/etc/lemper/cli-plugins"
    mkdir -p "${dest}" || return 1
    chmod 0700 "${dest}" 2>/dev/null || true

    install -m 0755 "${src}/bin/lemper-cli.sh" /usr/local/bin/lemper-cli || return 1
    ln -sfn /usr/local/bin/lemper-cli /usr/bin/lemper-cli

    while IFS=: read -r name target; do
        [[ -z "${name}" ]] && continue
        if [[ -f "${src}/lib/${name}.sh" ]]; then
            install -m 0755 "${src}/lib/${name}.sh" "${dest}/${target}" || return 1
        else
            warning "Missing ${src}/lib/${name}.sh; skipped."
        fi
    done <<'EOF'
lemper-account:lemper-account
lemper-adduser:lemper-adduser
lemper-site:lemper-site
lemper-site-list:lemper-site-list
lemper-site-show:lemper-site-show
lemper-create:lemper-site-create
lemper-manage:lemper-site-update
lemper-db:lemper-db
lemper-selfssl:lemper-selfssl
lemper-fixpermission:lemper-fixpermission
lemper-bench:lemper-bench
lemper-modsec:lemper-modsec
lemper-tui:lemper-tui
lemper-update:lemper-update
lemper-backup:lemper-backup
EOF

    ln -sfn "${dest}/lemper-site-create" "${dest}/lemper-site-add"
    ln -sfn "${dest}/lemper-site-update" "${dest}/lemper-site-mod"
    ln -sfn "${dest}/lemper-db" "${dest}/lemper-site-db"
    ln -sfn "${dest}/lemper-db" "${dest}/lemper-site-database"
    ln -sfn "${dest}/lemper-site-create" "${dest}/lemper-create"
    ln -sfn "${dest}/lemper-site-create" "${dest}/lemper-add"
    ln -sfn "${dest}/lemper-site-update" "${dest}/lemper-manage"
    ln -sfn "${dest}/lemper-site-update" "${dest}/lemper-mod"

    printf '%s\n' "${src}" > "${LEMPER_UPDATE_SOURCE_FILE}"
    chmod 0600 "${LEMPER_UPDATE_SOURCE_FILE}"

    reinstall_admin_tools "${src}" || return 1
    success "LEMPer CLI, plugins, and web administration tools reinstalled from ${src}."
}

##
# Report installed versions and PHP2Shell exposure without changing anything.
##
function update_check() {
    local branches branch installed state fixed pools mitigated rc=0
    local rows="" w_installed=17 w_state=5 w_fixed=5

    branches=$(php_installed_branches)
    if [[ -n "${branches}" ]]; then
        while IFS= read -r branch; do
            [[ -z "${branch}" ]] && continue
            installed=$(php_package_version "${branch}")
            installed="${installed:-unknown}"
            state=$(php_branch_state "${branch}" "${installed}")
            fixed=$(php_fixed_version "${branch}" 2>/dev/null || echo "-")
            pools=$(php_pool_count "${branch}")
            mitigated=$(php_pool_count "${branch}" "true")

            rows+="php${branch}"$'\t'"${installed}"$'\t'"${state}"
            rows+=$'\t'"${fixed}"$'\t'"${pools}"$'\t'"${mitigated}"$'\n'

            (( ${#installed} > w_installed )) && w_installed=${#installed}
            (( ${#state} > w_state )) && w_state=${#state}
            (( ${#fixed} > w_fixed )) && w_fixed=${#fixed}

            [[ "${state}" == "patched" ]] || rc=1
        done <<< "${branches}"
    fi

    echo "PHP2Shell (CVE-2026-109618 / CVE-2026-109619) status"
    echo "-----------------------------------------------------"

    if [[ -z "${rows}" ]]; then
        echo "  No PHP installation detected."
    else
        printf '  %-6s  %-*s  %-*s  %-*s  %s\n' \
            "Branch" "${w_installed}" "Installed version" \
            "${w_state}" "State" "${w_fixed}" "Fixed" "Pools (mitigated)"

        while IFS=$'\t' read -r branch installed state fixed pools mitigated; do
            [[ -z "${branch}" ]] && continue
            printf '  %-6s  %-*s  %-*s  %-*s  %s (%s)\n' \
                "${branch}" "${w_installed}" "${installed}" \
                "${w_state}" "${state}" "${w_fixed}" "${fixed}" \
                "${pools}" "${mitigated}"
        done <<< "${rows}"
    fi

    echo
    if command -v nginx >/dev/null 2>&1; then
        if dpkg -S "$(readlink -f "$(command -v nginx)" 2>/dev/null || command -v nginx)" >/dev/null 2>&1; then
            echo "  nginx:   package-managed ($(nginx -v 2>&1))"
        else
            echo "  nginx:   source build ($(nginx -v 2>&1)) - rebuild required"
        fi
    else
        echo "  nginx:   not installed"
    fi

    if dpkg -s mariadb-server >/dev/null 2>&1; then
        echo "  MariaDB: $(dpkg-query -W -f='${Version}' mariadb-server)"
    else
        echo "  MariaDB: not installed"
    fi

    if [[ -f /etc/lemper/cli-plugins/lemper-update ]]; then
        echo "  updater: installed"
    else
        echo "  updater: not installed"
    fi

    echo
    if [[ "${rc}" -eq 0 ]]; then
        echo "All installed PHP branches include the fix."
    else
        echo "Action required: patch supported branches and migrate EOL branches."
    fi

    return "${rc}"
}

##
# Run the full stack update.
##
function update_all() {
    local rc=0 nginx_repo_ready=0

    if ! retire_ondrej_nginx_sources; then
        error "Could not disable the retired Ondřej nginx repository."
        return 1
    fi
    if nginx_is_package_managed; then
        if ensure_myguard_nginx_repo; then
            nginx_repo_ready=1
        else
            warning "MyGuard nginx repository was not added; package-managed nginx will not be upgraded."
            rc=1
        fi
    fi
    if ! apt-get update -q; then
        error "apt-get update failed; aborting."
        return 1
    fi

    update_php || rc=1
    if [[ "${nginx_repo_ready}" -eq 1 ]] || ! nginx_is_package_managed; then
        update_nginx || rc=1
    fi
    update_mariadb || rc=1
    update_lemper_tooling || rc=1

    echo
    if [[ "${rc}" -eq 0 ]]; then
        success "Full stack update completed."
    else
        warning "Update finished with items requiring attention (see above)."
    fi

    return "${rc}"
}

##
# Help.
##
function update_help() {
    cat <<LEMPER_HELP
${CMD_PARENT} ${CMD_NAME} - patch PHP2Shell and keep the stack current

Usage: ${CMD_PARENT} ${CMD_NAME} [command] [options]

Commands:
  check                 Audit installed PHP, nginx, MariaDB, and updater state.
                        Exit 0 only when every PHP branch is patched.
  php                   Patch PHP-FPM packages. With --migrate-to=VERSION,
                        move EOL vhosts onto that PHP and create missing
                        FPM pools. Without it, mitigate EOL pools.
  nginx                 Upgrade package-managed nginx from the MyGuard
                        nginx-only repository and reload it. Retired Ondřej
                        nginx sources are disabled first. The Ondřej PHP
                        repository stays enabled.
  mariadb               Upgrade MariaDB packages and restart if changed.
  lemper                Reinstall the CLI, plugins, and web administration tools
                        from the recorded source (scripts/install_tools.sh).
  all                   Run every step above (default).

Options:
  -y, --yes             Accepted for unattended use (restarts are automatic).
  --migrate-to=VERSION  Move every EOL vhost to this PHP (8.2, 8.3, 8.4, or
                        8.5). The same switch is --force=VERSION. The target
                        PHP must already be installed. Old packages and pools
                        are left in place. Applies to update php and the php
                        step of update all.
  --source-dir=PATH     LEMPer checkout used for CLI/plugin refresh.
  --post-max-size=SIZE  post_max_size for EOL mitigations (default: 32M).
  -h, --help            Show this help.
  -v, --version         Output version information and exit.

Nginx repository:
  The Ondřej nginx PPA and packages.sury.org nginx suites are unpublished.
  Every apt refresh disables those sources. update nginx and the nginx step
  of update all then use https://deb.myguard.nl/apt/nginx/<codename> and keep
  existing /etc/nginx files. MyGuard nginx is mainline and links libssl-nginx
  beside the system OpenSSL. That package switch has not been verified on a
  live Ondřej install.

EOL mitigations (admin-locked per pool):
  memory_limit=-1, post_max_size=32M, session.upload_progress.enabled=0,
  and fatal_error_backtraces=0 on PHP 8.5. These are compensating controls,
  not a fix. Move the sites with:
    ${CMD_PARENT} ${CMD_NAME} php --migrate-to=8.3
  --force=8.3 is the same switch. A bare --force is rejected because the
  destination has to be explicit. Only EOL sockets and EOL
  \`set \$php_version\` lines change. Supported sockets stay. Each pool user
  is taken from the socket name (phpX.Y-fpm.USER.sock); a bare socket or a
  \`set \$php_version\` line uses the www pool. The destination pool is copied
  from the EOL pool when that file exists, and is created otherwise.
  Nginx is tested before it is reloaded. The previous vhosts are kept under
  ${LEMPER_BACKUP_DIR}/php-migrate-<UTC>/.
LEMPER_HELP
}

##
# Parse updater options. The destination version is required for a migration.
##
function update_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -y | --yes)
                UPDATE_ASSUME_YES=true
                shift
                ;;
            --source-dir=*)
                UPDATE_SOURCE_DIR="${1#*=}"
                shift
                ;;
            --post-max-size=*)
                PHP2SHELL_POST_MAX="${1#*=}"
                shift
                ;;
            --migrate-to=* | --force=*)
                PHP_MIGRATE_TO="${1#*=}"
                if [[ -z "${PHP_MIGRATE_TO}" ]]; then
                    error "A destination version is required. Use --migrate-to=8.3 or --force=8.3."
                    return 1
                fi
                shift
                ;;
            --migrate-to)
                if [[ $# -lt 2 || -z "${2}" || "${2}" == -* ]]; then
                    error "A destination version is required. Use --migrate-to=8.3 or --force=8.3."
                    return 1
                fi
                PHP_MIGRATE_TO="${2}"
                shift 2
                ;;
            --force)
                error "A destination version is required. Use --migrate-to=8.3 or --force=8.3."
                return 1
                ;;
            -h | --help)
                UPDATE_REQUESTED_SUBCOMMAND="help"
                shift
                ;;
            -v | --version)
                UPDATE_REQUESTED_SUBCOMMAND="version"
                shift
                ;;
            *)
                error "Unknown option: ${1}"
                update_help
                return 1
                ;;
        esac
    done
}

##
# Entry point.
##
function init_lemper_update() {
    local subcommand="${1:-all}"
    [[ $# -gt 0 ]] && shift

    update_parse_args "$@" || exit 1
    if [[ -n "${UPDATE_REQUESTED_SUBCOMMAND}" ]]; then
        subcommand="${UPDATE_REQUESTED_SUBCOMMAND}"
    fi

    if [[ ! "${PHP2SHELL_POST_MAX}" =~ ^[0-9]+[KMG]$ ]]; then
        fail "Invalid --post-max-size '${PHP2SHELL_POST_MAX}' (use e.g. 8M or 32M)."
    fi

    case "${subcommand}" in
        help | -h | --help)
            update_help
            ;;
        version | -v | --version)
            echo "${CMD_PARENT} ${CMD_NAME} version ${PROG_VERSION}"
            ;;
        check | status)
            update_check
            exit $?
            ;;
        php | nginx | mariadb | lemper | all)
            if command -v flock >/dev/null 2>&1; then
                exec 200>/var/lock/lemper-update.lock
                if ! flock -n 200; then
                    fail "Another LEMPer update is already running."
                fi
            fi

            mkdir -p "${LEMPER_LOG_DIR}" 2>/dev/null || true
            UPDATE_LOG="${LEMPER_LOG_DIR}/update-$(date -u +%Y%m%dT%H%M%SZ).log"
            if touch "${UPDATE_LOG}" 2>/dev/null; then
                chmod 0600 "${UPDATE_LOG}" 2>/dev/null || true
                info "Update log: ${UPDATE_LOG}"
                exec > >(tee -a "${UPDATE_LOG}") 2>&1
            fi

            case "${subcommand}" in
                php)
                    refresh_stack_apt || fail "apt-get update failed."
                    update_php
                    exit $?
                    ;;
                nginx)
                    refresh_nginx_apt || fail "Nginx update could not refresh package lists."
                    update_nginx
                    exit $?
                    ;;
                mariadb)
                    refresh_stack_apt || fail "apt-get update failed."
                    update_mariadb
                    exit $?
                    ;;
                lemper)
                    update_lemper_tooling
                    exit $?
                    ;;
                all)
                    update_all
                    exit $?
                    ;;
            esac
            ;;
        *)
            error "Unknown ${CMD_NAME} command: ${subcommand}"
            update_help
            exit 1
            ;;
    esac
}

# Allow unit tests to source the helpers without running the command.
if [[ "${LEMPER_UPDATE_LIB_ONLY:-false}" != "true" ]]; then
    init_lemper_update "$@"
fi
