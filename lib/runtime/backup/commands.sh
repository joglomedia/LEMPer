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
# Create a configuration backup.
##
function backup_create() {
    local output_dir="${LEMPER_BACKUP_DIR}"
    local label=""
    local archive

    lemper_parse_args 'h' 'output:,dir:,label:,help' "$@" || return 1
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
            --output=* | --dir=*)
                output_dir="${1#*=}"
                shift
                ;;
            --output | --dir)
                output_dir="${2:-}"
                shift 2
                ;;
            --label=*)
                label="${1#*=}"
                shift
                ;;
            --label)
                label="${2:-}"
                shift 2
                ;;
            -h | --help)
                backup_help
                return 0
                ;;
            *)
                error "Unknown ${CMD_NAME} create option: ${1}"
                return 1
                ;;
        esac
    done

    if [[ -z "${output_dir}" ]]; then
        error "Backup directory cannot be empty."
        return 1
    fi

    if ! archive=$(backup_create_archive "${output_dir}" "${label}"); then
        return 1
    fi

    if [[ "${DRYRUN}" == true ]]; then
        info "Dry run complete; no archive written."
        return 0
    fi

    success "Configuration backup created."
    echo "  Archive: ${archive}"
    echo "  Size:    $(du -h "${archive}" | cut -f1)"
    echo "  Members: $(tar -tzf "${archive}" | wc -l | tr -d ' ')"
    if [[ -f "${archive}.sha256" ]]; then
        echo "  SHA256:  $(awk '{print $1; exit}' "${archive}.sha256")"
    fi
    echo "  Restore: ${CMD_PARENT} ${CMD_NAME} restore --file ${archive}"
}

##
# List configuration archives.
##
function backup_list() {
    local dir="${LEMPER_BACKUP_DIR}"
    local file found=false

    lemper_parse_args 'h' 'dir:,help' "$@" || return 1
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
            --dir=*)
                dir="${1#*=}"
                shift
                ;;
            --dir)
                dir="${2:-}"
                shift 2
                ;;
            -h | --help)
                backup_help
                return 0
                ;;
            *)
                error "Unknown ${CMD_NAME} list option: ${1}"
                return 1
                ;;
        esac
    done

    echo "Configuration backups in ${dir}:"

    while IFS= read -r file; do
        if [[ -z "${file}" ]]; then
            continue
        fi
        found=true
        printf '  %-64s %8s\n' "$(basename "${file}")" "$(du -h "${file}" | cut -f1)"
    done < <(backup_archives "${dir}")

    if [[ "${found}" != true ]]; then
        info "No backups found. Run '${CMD_PARENT} ${CMD_NAME} create' first."
    fi
}

##
# Show archive metadata.
##
function backup_show() {
    local dir="${LEMPER_BACKUP_DIR}"
    local arg=""
    local file

    lemper_parse_args 'h' 'dir:,help' "$@" || return 1
    set -- "${LEMPER_PARSED_ARGS[@]}"

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --)
                shift
                [[ $# -le 1 ]] || {
                    error "Unexpected positional arguments."
                    return 1
                }
                [[ $# -eq 0 ]] || arg="${1}"
                break
                ;;
            --dir=*)
                dir="${1#*=}"
                shift
                ;;
            --dir)
                dir="${2:-}"
                shift 2
                ;;
            -h | --help)
                backup_help
                return 0
                ;;
            -*)
                error "Unknown ${CMD_NAME} show option: ${1}"
                return 1
                ;;
            *)
                arg="${1}"
                shift
                ;;
        esac
    done

    file=$(backup_resolve_archive "${arg}" "${dir}")

    if [[ -z "${file}" ]]; then
        error "No configuration archive found in ${dir}."
        return 1
    fi

    if ! backup_verify_archive "${file}"; then
        return 1
    fi

    echo "Archive:     ${file}"
    echo "Size:        $(du -h "${file}" | cut -f1)"
    echo "Members:     $(tar -tzf "${file}" | wc -l | tr -d ' ')"
    echo "Created:     $(backup_manifest_value CREATED_UTC "${file}")"
    echo "Hostname:    $(backup_manifest_value HOSTNAME "${file}")"
    echo "LEMPer:      $(backup_manifest_value LEMPER_VERSION "${file}")"
    echo "Backup root: $(backup_manifest_value BACKUP_ROOT "${file}")"
    echo "Paths:       $(backup_manifest_value PATHS "${file}")"
    echo "Legacy .env: $(backup_manifest_value LEGACY_ENV "${file}")"
}

##
# Verify an archive without changing the system.
##
function backup_verify() {
    local dir="${LEMPER_BACKUP_DIR}"
    local arg=""
    local file

    lemper_parse_args 'h' 'dir:,help' "$@" || return 1
    set -- "${LEMPER_PARSED_ARGS[@]}"

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --)
                shift
                [[ $# -le 1 ]] || {
                    error "Unexpected positional arguments."
                    return 1
                }
                [[ $# -eq 0 ]] || arg="${1}"
                break
                ;;
            --dir=*)
                dir="${1#*=}"
                shift
                ;;
            --dir)
                dir="${2:-}"
                shift 2
                ;;
            -h | --help)
                backup_help
                return 0
                ;;
            -*)
                error "Unknown ${CMD_NAME} verify option: ${1}"
                return 1
                ;;
            *)
                arg="${1}"
                shift
                ;;
        esac
    done

    file=$(backup_resolve_archive "${arg}" "${dir}")

    if [[ -z "${file}" ]]; then
        error "No configuration archive found in ${dir}."
        return 1
    fi

    if ! backup_verify_archive "${file}"; then
        return 1
    fi

    success "Archive verified: ${file}"
    echo "  Members: $(tar -tzf "${file}" | wc -l | tr -d ' ')"
}

##
# Restore a configuration archive.
##
function backup_restore() {
    local dir="${LEMPER_BACKUP_DIR}"
    local file=""
    local arg=""
    local assume_yes=false
    local dry_run="${DRYRUN}"
    local snapshot=true
    local reload=false
    local root snapshot_archive answer unit excludes=()

    lemper_parse_args 'hy' 'dir:,file:,latest,yes,dry-run,no-snapshot,reload,help' "$@" || return 1
    set -- "${LEMPER_PARSED_ARGS[@]}"

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --)
                shift
                [[ $# -le 1 ]] || {
                    error "Unexpected positional arguments."
                    return 1
                }
                [[ $# -eq 0 ]] || arg="${1}"
                break
                ;;
            --dir=*)
                dir="${1#*=}"
                shift
                ;;
            --dir)
                dir="${2:-}"
                shift 2
                ;;
            --file=*)
                arg="${1#*=}"
                shift
                ;;
            --file)
                arg="${2:-}"
                shift 2
                ;;
            --latest)
                arg="latest"
                shift
                ;;
            -y | --yes)
                assume_yes=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --no-snapshot)
                snapshot=false
                shift
                ;;
            --reload)
                reload=true
                shift
                ;;
            -h | --help)
                backup_help
                return 0
                ;;
            -*)
                error "Unknown ${CMD_NAME} restore option: ${1}"
                return 1
                ;;
            *)
                if [[ -n "${arg}" ]]; then
                    error "Only one archive may be restored at a time."
                    return 1
                fi
                arg="${1}"
                shift
                ;;
        esac
    done

    if [[ -z "${arg}" ]]; then
        error "Specify an archive, --file <path>, or --latest."
        backup_list --dir "${dir}"
        return 1
    fi

    file=$(backup_resolve_archive "${arg}" "${dir}")

    if [[ -z "${file}" ]]; then
        error "No configuration archive found for '${arg}'."
        return 1
    fi

    if ! backup_verify_archive "${file}"; then
        error "Refusing to restore an unverified archive."
        return 1
    fi

    root=$(backup_root)

    if [[ "${dry_run}" == true ]]; then
        info "Dry run: would restore $(tar -tzf "${file}" | wc -l | tr -d ' ') members from ${file} into ${root}."
        if [[ "${snapshot}" == true ]]; then
            info "A pre-restore snapshot would be written to ${dir}."
        fi
        return 0
    fi

    if [[ "${assume_yes}" != true ]]; then
        if [[ ! -t 0 ]]; then
            error "Restoring requires --yes when no terminal is attached."
            return 1
        fi

        read -r -p "Restore ${file} into ${root}? Existing files are overwritten. [y/N]: " answer
        case "${answer}" in
            y | Y | yes | YES) ;;
            *)
                info "Restore cancelled."
                return 1
                ;;
        esac
    fi

    snapshot_archive=""
    if [[ "${snapshot}" == true ]]; then
        if ! snapshot_archive=$(backup_create_archive "${dir}" "pre-restore"); then
            error "Could not create a pre-restore snapshot; aborting."
            return 1
        fi
    fi

    excludes=(
        "--exclude=${LEMPER_BACKUP_MANIFEST}"
        "--exclude=etc/lemper/core"
        "--exclude=etc/lemper/runtime"
        "--exclude=etc/lemper/services"
        "--exclude=etc/lemper/compat"
        "--exclude=etc/lemper/cli-plugins"
        "--exclude=etc/lemper/backups"
    )

    lemper_load_module core/progress || return 1
    if ! (
        set -o pipefail
        lemper_transfer_read "${file}" | tar -xz -C "${root}" --numeric-owner "${excludes[@]}"
    ); then
        error "Restore failed while extracting ${file}."
        if [[ -n "${snapshot_archive}" ]]; then
            warning "Pre-restore snapshot: ${snapshot_archive}"
        fi
        return 1
    fi

    # Only validate the live system; the backup root override is for tests.
    if [[ "${root}" == "/" ]] && command -v nginx >/dev/null 2>&1 \
        && [[ -f /etc/nginx/nginx.conf ]]; then
        if ! nginx -t >/dev/null 2>&1; then
            error "Nginx configuration test failed after restore."

            if [[ -n "${snapshot_archive}" ]]; then
                warning "Rolling back to the pre-restore snapshot..."
                tar -xzf "${snapshot_archive}" -C "${root}" --numeric-owner \
                    --exclude="${LEMPER_BACKUP_MANIFEST}" || true
                error "Restore rolled back; the previous configuration was kept."
            fi
            return 1
        fi
    fi

    if [[ "${reload}" == true && "${root}" == "/" ]] && command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet nginx; then
            systemctl reload nginx || warning "Could not reload nginx."
        fi

        while IFS= read -r unit; do
            if [[ -z "${unit}" ]]; then
                continue
            fi
            systemctl reload "${unit}" || warning "Could not reload ${unit}."
        done < <(systemctl list-units --type=service --state=active --plain --no-legend \
            'php*-fpm.service' 2>/dev/null | awk '{print $1}')
    fi

    success "Configuration restored from ${file}."
    if [[ -n "${snapshot_archive}" ]]; then
        echo "  Pre-restore snapshot: ${snapshot_archive}"
    fi
    if [[ "${reload}" != true ]]; then
        echo "  Reload services when ready: systemctl reload nginx; systemctl list-units 'php*-fpm'"
    fi
}

##
# Delete old archives, keeping the newest N.
##
function backup_prune() {
    local dir="${LEMPER_BACKUP_DIR}"
    local keep="${LEMPER_BACKUP_KEEP}"
    local assume_yes=false
    local file index=0 removed=0 answer
    local doomed=()

    lemper_parse_args 'hy' 'dir:,keep:,yes,help' "$@" || return 1
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
            --dir=*)
                dir="${1#*=}"
                shift
                ;;
            --dir)
                dir="${2:-}"
                shift 2
                ;;
            --keep=*)
                keep="${1#*=}"
                shift
                ;;
            --keep)
                keep="${2:-}"
                shift 2
                ;;
            -y | --yes)
                assume_yes=true
                shift
                ;;
            -h | --help)
                backup_help
                return 0
                ;;
            *)
                error "Unknown ${CMD_NAME} prune option: ${1}"
                return 1
                ;;
        esac
    done

    if [[ ! "${keep}" =~ ^[0-9]+$ ]] || [[ "${keep}" -lt 1 ]]; then
        error "Invalid --keep value '${keep}'; use a positive integer."
        return 1
    fi

    while IFS= read -r file; do
        if [[ -z "${file}" ]]; then
            continue
        fi
        index=$((index + 1))
        if [[ "${index}" -gt "${keep}" ]]; then
            doomed+=("${file}")
        fi
    done < <(backup_archives "${dir}")

    if [[ ${#doomed[@]} -eq 0 ]]; then
        info "Nothing to prune; ${dir} already keeps ${keep} or fewer archives."
        return 0
    fi

    echo "Archives to delete:"
    for file in "${doomed[@]}"; do
        echo "  ${file}"
    done

    if [[ "${assume_yes}" != true ]]; then
        if [[ ! -t 0 ]]; then
            error "Pruning requires --yes when no terminal is attached."
            return 1
        fi

        read -r -p "Delete ${#doomed[@]} archive(s)? [y/N]: " answer
        case "${answer}" in
            y | Y | yes | YES) ;;
            *)
                info "Prune cancelled."
                return 1
                ;;
        esac
    fi

    for file in "${doomed[@]}"; do
        rm -f "${file}" "${file}.sha256"
        removed=$((removed + 1))
    done

    success "Removed ${removed} archive(s) from ${dir}."
}

##
# Print help.
##
function backup_help() {
    cat <<-EOL
${CMD_PARENT} ${CMD_NAME} ${PROG_VERSION}
LEMPer configuration backup and restore.

Usage: ${CMD_PARENT} ${CMD_NAME} <command> [options]

Commands:
  create [options]         Archive LEMPer-managed configuration (default).
  list [--dir DIR]         List configuration archives.
  show [archive|latest]    Print an archive manifest.
  verify [archive|latest]  Check integrity and the restore allow-list.
  restore [options]        Restore an archive; snapshots first by default.
  prune [options]          Delete old archives.

General options:
  -h, --help               Show this help.
  -v, --version            Output version information and exit.

Create options:
  --output DIR, --dir DIR  Archive directory (default: ${LEMPER_BACKUP_DIR}).
  --label TEXT             Suffix for the archive name.

Restore options:
  --file PATH              Archive to restore.
  --latest                 Restore the newest archive.
  --dry-run                Show what would be restored.
  --no-snapshot            Skip the automatic pre-restore snapshot.
  --reload                 Reload Nginx and PHP-FPM after a successful test.
  -y, --yes                Skip the confirmation prompt.

Prune options:
  --keep N                 Number of archives to keep (default: ${LEMPER_BACKUP_KEEP}).
  -y, --yes                Skip the confirmation prompt.

What is archived:
  /etc/lemper (without cli-plugins and php2shell copies), Nginx, PHP,
  MySQL/MariaDB, PostgreSQL, MongoDB, Redis/Valkey, Memcached, Fail2ban,
  CrowdSec, ModSecurity tuning, Let's Encrypt, mail, FTP, and legacy .env.

Archives contain credentials and private keys. They are created mode 0600 in
a mode 0700 directory; keep them root-only and off public web roots.
EOL
}

##
# Main entry point.
##
function init_lemper_backup() {
    local subcommand="${1:-create}"

    if [[ $# -gt 0 ]]; then
        shift
    fi

    case "${subcommand}" in
        create | backup)
            backup_create "$@"
            ;;
        list | ls)
            backup_list "$@"
            ;;
        show | inspect)
            backup_show "$@"
            ;;
        verify | check)
            backup_verify "$@"
            ;;
        restore)
            backup_restore "$@"
            ;;
        prune)
            backup_prune "$@"
            ;;
        help | -h | --help)
            backup_help
            ;;
        version | -v | --version)
            echo "${CMD_PARENT} ${CMD_NAME} version ${PROG_VERSION}"
            ;;
        *)
            error "Unknown ${CMD_NAME} command: ${subcommand}"
            backup_help
            return 1
            ;;
    esac
}

# shellcheck disable=SC2034 # State is shared with the named service driver.
function lemper_backup_initialize() {
    LEMPER_BACKUP_ROOT="${LEMPER_BACKUP_ROOT:-/}"
    LEMPER_BACKUP_DIR="${LEMPER_BACKUP_DIR:-/var/backups/lemper/config}"
    LEMPER_BACKUP_KEEP="${LEMPER_BACKUP_KEEP:-10}"
    LEMPER_BACKUP_MANIFEST="LEMPER-BACKUP-MANIFEST"
    LEMPER_BACKUP_FORMAT=1
    LEMPER_BACKUP_PATHS_DEFAULT=(
        etc/lemper
        etc/nginx
        etc/php
        etc/mysql
        etc/postgresql
        etc/mongod.conf
        etc/redis
        etc/valkey
        etc/default/redis-server
        etc/default/valkey-server
        etc/memcached.conf
        etc/memcached
        etc/sasl2
        etc/fail2ban
        etc/crowdsec
        etc/modsecurity
        etc/letsencrypt
        etc/vsftpd.conf
        etc/vsftpd.userlist
        etc/ftpusers
        etc/pure-ftpd
        etc/pam.d/pure-ftpd
        etc/pam.d/vsftpd
        etc/default/pure-ftpd-common
        etc/lemper-mail
        etc/postfix
        etc/dovecot
        etc/aliases
        etc/default/opendkim
        etc/opendkim.conf
        etc/opendkim
        etc/logrotate.d/php
        etc/logrotate.d/certbot
        etc/profile.d/bun.sh
        etc/profile.d/mail.sh
        etc/ssl/private/pure-ftpd.pem
        etc/ssl/private/vsftpd-selfsigned.pem
        etc/systemd/system/pure-ftpd.service
        usr/lib/systemd/system/vsftpd.service
    )
    LEMPER_BACKUP_EXCLUDES_DEFAULT=(
        etc/lemper/core
        etc/lemper/runtime
        etc/lemper/services
        etc/lemper/compat
        etc/lemper/cli-plugins
        etc/lemper/backups
        etc/modsecurity/crs
    )
}
