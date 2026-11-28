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

    if [[ "${line}" =~ set[[:space:]]+\$php_version[[:space:]]+\"([0-9]+\.[0-9]+)\" ]] \
        || [[ "${line}" =~ set[[:space:]]+\$php_version[[:space:]]+\'([0-9]+\.[0-9]+)\' ]] \
        || [[ "${line}" =~ set[[:space:]]+\$php_version[[:space:]]+([0-9]+\.[0-9]+)([^0-9.]|$) ]]; then
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
    if command -v readlink >/dev/null 2>&1; then
        readlink -f -- "${path}" 2>/dev/null && return 0
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
    done <"${manifest}"
}

##
# Rewrite phpX.Y path and extension-suffix tokens from one branch to another.
##
function php_rewrite_pool_text() {
    local from="${1}" to="${2}" log_dir="${3}"
    local from_pattern="${from//./[.]}" from_compact="${from//./}" to_compact="${to//./}"
    awk -v from="$from_pattern" -v to="$to" -v from_compact="$from_compact" -v to_compact="$to_compact" -v log_dir="$log_dir" '
        /^[[:space:]]*slowlog[[:space:]]*=/ { print "slowlog = " log_dir "/php" to "-fpm_slow.log"; next }
        /^[[:space:]]*access\.log[[:space:]]*=/ { print "access.log = " log_dir "/php" to "-fpm_access.log"; next }
        /^[[:space:]]*php_(admin_)?value\[error_log\][[:space:]]*=/ {
            print "php_admin_value[error_log] = " log_dir "/php" to "-fpm_error.log"; next
        }
        /^[[:space:]]*php_(admin_)?value\[opcache\.error_log\][[:space:]]*=/ {
            print "php_admin_value[opcache.error_log] = " log_dir "/php" to "-opcache_error.log"; next
        }
        {
            gsub("php" from, "php" to)
            gsub("[.]php" from_compact, ".php" to_compact)
            print
        }
    '
}

##
# Minimal pool used when the EOL branch has no pool file for this user.
##
function php_minimal_pool_text() {
    local pool="${1}" version="${2}" log_dir="${3}"
    local user="${pool}" group="${4}" home="/home/${pool}" listen_name=".${pool}"
    local state_dir="${LEMPER_PHP_STATE_DIR:-/var/lib/php/lemper}/$pool"

    if [[ "${pool}" == "www" ]]; then
        user="www-data"
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
php_admin_value[error_log] = ${log_dir}/php${version}-fpm_error.log
php_admin_value[open_basedir] = ${home}:${state_dir}:${log_dir}
php_admin_value[sys_temp_dir] = ${state_dir}/tmp
php_admin_value[upload_tmp_dir] = ${state_dir}/tmp
php_admin_value[session.save_path] = ${state_dir}/sessions
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
    local root="${LEMPER_PHP_STATE_DIR:-/var/lib/php/lemper}" owner="$2" uid="$3" gid="$4"
    local base="$root/$pool" owner_mode

    lemper_directory_trusted "$root" && mkdir -p -- "$root" || return 1
    [[ ! -L "$base" ]] || return 1
    if [[ ! -e "$base" ]]; then
        install -d -m 0700 -o "$uid" -g "$gid" -- "$base" || return 1
    fi
    owner_mode=$(stat -c '%u %a' -- "$base") || return 1
    [[ -d "$base" && "$owner_mode" == "$uid 700" ]] || return 1
    (cd -- "$base" && runuser -u "$owner" -- mkdir -p -m 0700 -- tmp sessions wsdlcache opcache)
}

##
# Create the destination pool from the EOL pool, or from a minimal template.
##
function php_ensure_migrated_pool() {
    local pool="${1}" from="${2}" to="${3}"
    local dest="${PHP_ETC_DIR}/${to}/fpm/pool.d/${pool}.conf"
    local src="${PHP_ETC_DIR}/${from}/fpm/pool.d/${pool}.conf"
    local temporary owner="$pool" uid group gid mode log_root="${LEMPER_PHP_LOG_DIR:-/var/log/lemper/php}"

    [[ "$from" =~ ^[0-9]+\.[0-9]+$ && "$to" =~ ^[0-9]+\.[0-9]+$ &&
        "$log_root" =~ ^/[[:alnum:]_./-]+$ ]] && is_valid_username "$pool" || return 1
    if ! lemper_directory_trusted "${dest%/*}" || ! lemper_directory_trusted "${src%/*}"; then
        error "PHP pool configuration requires protected source and destination directories."
        return 1
    fi
    [[ ! -L "$src" && ! -L "$dest" ]] || return 1
    if [[ -f "${dest}" ]]; then
        mode=$(stat -c '%a' -- "$dest") || return 1
        [[ "$(stat -c '%u' -- "$dest")" == "$EUID" ]] && (((8#$mode & 0022) == 0)) || return 1
        info "PHP ${to} pool ${pool} already exists."
        return 0
    fi
    [[ ! -e "$dest" && (! -e "$src" || -f "$src") ]] || return 1
    if [[ -f "$src" ]]; then
        mode=$(stat -c '%a' -- "$src") || return 1
        [[ "$(stat -c '%u' -- "$src")" == "$EUID" ]] && (((8#$mode & 0022) == 0)) || return 1
    fi
    [[ "$pool" != www ]] || owner=www-data
    uid=$(id -u "$owner") && gid=$(id -g "$owner") && group=$(id -gn "$owner") && [[ "$uid" =~ ^[1-9][0-9]*$ ]] || {
        error "PHP pool $pool does not have a valid unprivileged account."
        return 1
    }
    mkdir -p "${PHP_ETC_DIR}/${to}/fpm/pool.d" || return 1
    temporary=$(mktemp "${dest}.XXXXXXXX") || return 1
    if [[ -f "${src}" ]]; then
        php_rewrite_pool_text "$from" "$to" "$log_root/$pool" <"$src" >"$temporary" || {
            rm -f -- "$temporary"
            return 1
        }
    else
        php_minimal_pool_text "$pool" "$to" "$log_root/$pool" "$group" >"$temporary" || {
            rm -f -- "$temporary"
            return 1
        }
    fi
    if ! php_migrate_prepare_pool_dirs "$pool" "$owner" "$uid" "$gid" \
        || ! php_migrate_prepare_log_dir "$log_root/$pool" "$to" "$uid" "$gid" \
        || ! mv -T -- "$temporary" "$dest"; then
        rm -f -- "$temporary"
        return 1
    fi
    info "Created PHP $to pool $pool."
}

##
# Keep FPM master logs and worker log paths under protected ancestry.
##
function php_migrate_prepare_log_dir() {
    local log_dir="$1" version="$2" uid="$3" gid="$4" file kind owner
    lemper_directory_trusted "$log_dir" || return 1
    install -d -m 0750 -o root -g "$gid" -- "$log_dir" || return 1
    for kind in fpm_access fpm_slow fpm_error opcache_error; do
        file="$log_dir/php$version-$kind.log"
        owner=0
        case "$kind" in fpm_error | opcache_error) owner="$uid" ;; esac
        [[ ! -L "$file" ]] || return 1
        if [[ -e "$file" ]]; then
            [[ -f "$file" && "$(stat -c '%u %a %h' -- "$file")" == "$owner 600 1" ]] || return 1
        else
            install -m 0600 -o "$owner" -g "$gid" /dev/null "$file" || return 1
        fi
    done
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
    if [[ "$sites" == /etc/nginx/sites-available ]] \
        && { [[ "$(php_branch_state "$target" "$(php_package_version "$target")")" != patched ]] \
            || [[ "$(php_fpm_runtime_state "$target")" != current ]]; }; then
        error "PHP $target must be patched and running its installed FPM binary before migration."
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
        : >"${tmp}"
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
                done <<<"$(php_eol_socket_pairs "${line}")"
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
            printf '%s\n' "${new_line}" >>"${tmp}"
        done <"${vhost}"
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
            : >"${manifest}"
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
        if ! cat "${tmp}" >"${vhost}"; then
            rm -f "${tmp}"
            php_migrate_restore_manifest "${manifest}"
            return 1
        fi
        rm -f "${tmp}"
        printf '%s\t%s\n' "${backup_file}" "${vhost}" >>"${manifest}"
        info "Migrated EOL PHP handlers in ${vhost} to PHP ${target}."
    done

    if [[ -z "${backup_dir}" ]]; then
        info "No EOL PHP sockets found in Nginx vhosts."
        return 0
    fi

    # Unit tests point the sites directory at a fixture. Only a real
    # sites-available tree is allowed to invoke the local nginx binary.
    if [[ "${sites}" == "/etc/nginx/sites-available" ]]; then
        if ! command -v nginx >/dev/null 2>&1 || ! nginx -t; then
            error "nginx configuration test failed; restoring vhosts."
            php_migrate_restore_manifest "${manifest}"
            return 1
        fi
        if ! php_reload_branch "$target" || [[ "$(php_fpm_runtime_state "$target")" != current ]] \
            || ! systemctl reload nginx; then
            error "Could not activate the PHP $target handlers; restoring vhosts."
            php_migrate_restore_manifest "$manifest"
            systemctl reload nginx || error "Could not reload restored Nginx configuration."
            return 1
        fi
    fi

    success "EOL vhosts now use PHP ${target}. Previous vhosts: ${backup_dir}."
    warning "The old PHP packages and pools are still installed. Stop those FPM services after the sites answer on PHP ${target}."
}
