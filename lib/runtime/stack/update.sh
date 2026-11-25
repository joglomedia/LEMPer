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
    if [[ -n "${PHP_UPDATE_VERSION:-}" ]]; then
        if ! grep -Fxq "${PHP_UPDATE_VERSION}" <<<"${branches}"; then
            error "PHP ${PHP_UPDATE_VERSION} is not installed."
            return 1
        fi
        branches="${PHP_UPDATE_VERSION}"
    fi
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
    done <<<"${branches}"

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

##
# Report installed versions and PHP2Shell exposure without changing anything.
##
function update_check() {
    local branches branch installed state fixed pools mitigated rc=0
    local rows="" w_installed=17 w_state=5 w_fixed=5

    branches=$(php_installed_branches)
    if [[ -n "${PHP_UPDATE_VERSION:-}" ]]; then
        if ! grep -Fxq "${PHP_UPDATE_VERSION}" <<<"${branches}"; then
            error "PHP ${PHP_UPDATE_VERSION} is not installed."
            return 1
        fi
        branches="${PHP_UPDATE_VERSION}"
    fi
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

            ((${#installed} > w_installed)) && w_installed=${#installed}
            ((${#state} > w_state)) && w_state=${#state}
            ((${#fixed} > w_fixed)) && w_fixed=${#fixed}

            [[ "${state}" == "patched" ]] || rc=1
        done <<<"${branches}"
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
        done <<<"${rows}"
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
    refresh_php_apt_source || return 1
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
                        nginx sources are disabled first. Existing PHP sources
                        migrate to the maintained Sury archive.
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
  --php-version=VERSION  Limit PHP patch/remediation to one installed branch.
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
    # Keep the legacy explicit-destination diagnostic for a bare --force.
    local argument
    for argument in "$@"; do
        [[ "${argument}" != --force ]] || {
            error "A destination version is required. Use --migrate-to=8.3 or --force=8.3."
            return 1
        }
    done
    lemper_parse_args 'yhv' 'yes,source-dir:,post-max-size:,migrate-to:,force:,php-version:,help,version' "$@" || return 1
    set -- "${LEMPER_PARSED_ARGS[@]}"

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --)
                shift
                [[ $# -eq 0 ]] || {
                    error "Unexpected positional arguments."
                    return 1
                }
                break
                ;;
            -y | --yes)
                UPDATE_ASSUME_YES=true
                shift
                ;;
            --source-dir)
                UPDATE_SOURCE_DIR="${2}"
                shift 2
                ;;
            --php-version)
                [[ "${2}" =~ ^[0-9]+\.[0-9]+$ ]] || {
                    error "Invalid PHP version."
                    return 1
                }
                PHP_UPDATE_VERSION="${2}"
                shift 2
                ;;
            --post-max-size)
                PHP2SHELL_POST_MAX="${2}"
                shift 2
                ;;
            --migrate-to=* | --force=*)
                PHP_MIGRATE_TO="${1#*=}"
                if [[ -z "${PHP_MIGRATE_TO}" ]]; then
                    error "A destination version is required. Use --migrate-to=8.3 or --force=8.3."
                    return 1
                fi
                shift
                ;;
            --migrate-to | --force)
                if [[ $# -lt 2 || -z "${2}" || "${2}" == -* ]]; then
                    error "A destination version is required. Use --migrate-to=8.3 or --force=8.3."
                    return 1
                fi
                PHP_MIGRATE_TO="${2}"
                shift 2
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
function init_lemper_update() (
    local subcommand="${1:-all}"
    [[ $# -gt 0 ]] && shift

    PHP_UPDATE_VERSION=""
    update_parse_args "$@" || return 1
    if [[ -n "${PHP_UPDATE_VERSION}" && "${subcommand}" != php ]]; then
        error "--php-version requires update php."
        return 1
    fi
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
            return $?
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
                    return $?
                    ;;
                nginx)
                    refresh_nginx_apt || fail "Nginx update could not refresh package lists."
                    update_nginx
                    return $?
                    ;;
                mariadb)
                    refresh_stack_apt || fail "apt-get update failed."
                    update_mariadb
                    return $?
                    ;;
                lemper)
                    update_lemper_tooling
                    return $?
                    ;;
                all)
                    update_all
                    return $?
                    ;;
            esac
            ;;
        *)
            error "Unknown ${CMD_NAME} command: ${subcommand}"
            update_help
            return 1
            ;;
    esac
)

# shellcheck disable=SC2034 # Defaults initialize state shared with the named update drivers.
function lemper_update_initialize() {
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
}
