#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Security & Stack Updater                                   |
# +-------------------------------------------------------------------------+
# | Patches PHP2Shell (CVE-2026-109618 / CVE-2026-109619) and keeps the      |
# | rest of the stack current. Legacy (EOL) PHP branches have no vendor      |
# | patch, so their pools receive admin-locked compensating controls and     |
# | are reported as requiring migration.                                    |
# |                                                                          |
# | Invoked as: lemper-cli update <check|php|nginx|mariadb|lemper|all>       |
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
# Upgrade a patched PHP branch and verify the running package version.
##
function php_patch_branch() {
    local branch="${1}"
    local fixed="${2}"
    local pkgs=()
    local pkg installed

    while IFS= read -r pkg; do
        [[ -n "${pkg}" ]] && pkgs+=("${pkg}")
    done < <(dpkg-query -W -f='${Package}\n' "php${branch}-*" 2>/dev/null || true)

    if [[ "${#pkgs[@]}" -eq 0 ]]; then
        pkgs=("php${branch}-fpm" "php${branch}-cli" "php${branch}-common")
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
# Patch supported PHP branches and mitigate EOL branches.
##
function update_php() {
    local branches branch installed state fixed rc=0

    branches=$(php_installed_branches)
    if [[ -z "${branches}" ]]; then
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
                warning "PHP ${branch} is EOL and has no vendor patch for PHP2Shell."
                php_mitigate_branch "${branch}" || rc=1
                warning "PHP ${branch} remains exploitable; migrate its pools to PHP 8.2 or newer."
                rc=1
                ;;
            *)
                warning "Unable to determine the PHP ${branch} version."
                rc=1
                ;;
        esac
    done <<< "${branches}"

    return "${rc}"
}

##
# Upgrade installed nginx packages (source builds must be rebuilt).
##
function update_nginx() {
    local bin real pkgs=() pkg

    if ! bin=$(command -v nginx); then
        info "nginx is not installed."
        return 0
    fi

    real=$(readlink -f "${bin}" 2>/dev/null || echo "${bin}")
    if ! dpkg -S "${real}" >/dev/null 2>&1; then
        warning "nginx at ${bin} is not package-managed (source build); rebuild nginx to apply updates."
        return 1
    fi

    while IFS= read -r pkg; do
        [[ -n "${pkg}" ]] && pkgs+=("${pkg}")
    done < <(dpkg-query -W -f='${Package}\n' 'nginx*' 'libnginx-mod-*' 2>/dev/null || true)

    if [[ "${#pkgs[@]}" -eq 0 ]]; then
        info "No nginx packages found to upgrade."
        return 0
    fi

    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -q --only-upgrade "${pkgs[@]}"; then
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
lemper-encrypt:lemper-encrypt
lemper-update:lemper-update
EOF

    ln -sfn "${dest}/lemper-site-create" "${dest}/lemper-site-add"
    ln -sfn "${dest}/lemper-site-update" "${dest}/lemper-site-mod"
    ln -sfn "${dest}/lemper-db" "${dest}/lemper-site-db"
    ln -sfn "${dest}/lemper-db" "${dest}/lemper-site-database"

    printf '%s\n' "${src}" > "${LEMPER_UPDATE_SOURCE_FILE}"
    chmod 0600 "${LEMPER_UPDATE_SOURCE_FILE}"

    success "LEMPer CLI and plugins refreshed from ${src}."
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
    local rc=0

    if ! apt-get update -q; then
        error "apt-get update failed; aborting."
        return 1
    fi

    update_php || rc=1
    update_nginx || rc=1
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
  php                   Patch PHP-FPM packages; mitigate EOL branches.
  nginx                 Upgrade package-managed nginx and reload it.
  mariadb               Upgrade MariaDB packages and restart if changed.
  lemper                Refresh the LEMPer CLI/plugins from the recorded source.
  all                   Run every step above (default).

Options:
  -y, --yes             Accepted for unattended use (restarts are automatic).
  --source-dir=PATH     LEMPer checkout used for CLI/plugin refresh.
  --post-max-size=SIZE  post_max_size for EOL mitigations (default: 32M).
  -h, --help            Show this help.

EOL mitigations (admin-locked per pool):
  memory_limit=-1, post_max_size=32M, session.upload_progress.enabled=0,
  and fatal_error_backtraces=0 on PHP 8.5. These are compensating controls,
  not a fix; migrate to PHP 8.2.35+, 8.3.36+, 8.4.27+, or 8.5.12+.
LEMPER_HELP
}

##
# Entry point.
##
function init_lemper_update() {
    local subcommand="${1:-all}"
    [[ $# -gt 0 ]] && shift

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
            -h | --help)
                subcommand="help"
                shift
                ;;
            *)
                error "Unknown option: ${1}"
                update_help
                exit 1
                ;;
        esac
    done

    if [[ ! "${PHP2SHELL_POST_MAX}" =~ ^[0-9]+[KMG]$ ]]; then
        fail "Invalid --post-max-size '${PHP2SHELL_POST_MAX}' (use e.g. 8M or 32M)."
    fi

    case "${subcommand}" in
        help | -h | --help)
            update_help
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
                    apt-get update -q || fail "apt-get update failed."
                    update_php
                    exit $?
                    ;;
                nginx)
                    apt-get update -q || fail "apt-get update failed."
                    update_nginx
                    exit $?
                    ;;
                mariadb)
                    apt-get update -q || fail "apt-get update failed."
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
