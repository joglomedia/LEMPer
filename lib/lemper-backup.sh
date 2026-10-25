#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Configuration Backup & Restore                             |
# +-------------------------------------------------------------------------+
# | Archives the configuration LEMPer manages — Nginx, PHP, databases,      |
# | security tooling, LEMPer itself, and legacy .env files — so a broken    |
# | change can be rolled back.                                              |
# |                                                                         |
# | Invoked as: lemper-cli backup <create|list|show|verify|restore|prune>   |
# +-------------------------------------------------------------------------+

# Version control.
CMD_PARENT="${PROG_NAME}"
CMD_NAME="backup"

# Make sure only root can access and not direct access.
if [[ "$(type -t requires_root)" != "function" ]]; then
    echo "Direct access to this script is not permitted."
    exit 1
fi

LEMPER_BACKUP_ROOT="${LEMPER_BACKUP_ROOT:-/}"
LEMPER_BACKUP_DIR="${LEMPER_BACKUP_DIR:-/var/backups/lemper/config}"
LEMPER_BACKUP_KEEP="${LEMPER_BACKUP_KEEP:-10}"
LEMPER_BACKUP_MANIFEST="LEMPER-BACKUP-MANIFEST"
LEMPER_BACKUP_FORMAT=1

# Configuration roots archived by default, relative to the backup root.
# Web content, database data, logs, and CLI plugin code are deliberately
# left out: this archive restores behavior, not application data.
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

# Package-managed trees and LEMPer's own rollback copies are excluded.
# CLI plugins are code, so restoring them could silently downgrade the CLI.
LEMPER_BACKUP_EXCLUDES_DEFAULT=(
    etc/lemper/cli-plugins
    etc/lemper/backups
    etc/modsecurity/crs
)

##
# Return the backup root without a trailing slash.
##
function backup_root() {
    local root="${LEMPER_BACKUP_ROOT}"

    if [[ "${root}" == "/" ]]; then
        printf '/\n'
    else
        printf '%s\n' "${root%/}"
    fi
}

##
# Convert an absolute path inside the backup root to an archive member.
##
function backup_member_name() {
    local abs="${1}"
    local root

    root=$(backup_root)

    if [[ "${root}" == "/" ]]; then
        printf '%s\n' "${abs#/}"
    else
        printf '%s\n' "${abs#"${root}"/}"
    fi
}

##
# List the configuration roots, honouring the LEMPER_BACKUP_PATHS override.
##
function backup_path_list() {
    local path

    if [[ -n "${LEMPER_BACKUP_PATHS:-}" ]]; then
        # Word splitting is intentional: the override is a space-separated list.
        # shellcheck disable=SC2086
        for path in ${LEMPER_BACKUP_PATHS}; do
            printf '%s\n' "${path}"
        done
    else
        printf '%s\n' "${LEMPER_BACKUP_PATHS_DEFAULT[@]}"
    fi
}

##
# Print candidate legacy .env locations.
#
# LEMPer 3.x keeps its configuration in /etc/lemper/lemper.conf, but 2.x and
# early 3.x installs kept a .env in the checkout. The recorded update source is
# checked first, then the common clone locations.
##
function backup_legacy_candidates() {
    local src

    if [[ -n "${LEMPER_LEGACY_DIR:-}" ]]; then
        printf '%s\n' "${LEMPER_LEGACY_DIR%/}/.env"
        return 0
    fi

    if [[ -r /etc/lemper/update-source ]]; then
        src=$(head -n 1 /etc/lemper/update-source 2>/dev/null)
        if [[ -n "${src}" ]]; then
            printf '%s\n' "${src%/}/.env"
        fi
    fi

    printf '%s\n' \
        /etc/lemper/.env \
        /root/lemper/.env \
        /root/LEMPer/.env \
        /opt/lemper/.env \
        /opt/LEMPer/.env \
        /srv/lemper/.env \
        /usr/local/lemper/.env \
        /usr/local/src/lemper/.env \
        /var/www/lemper/.env \
        /var/www/html/lemper/.env
}

##
# List existing legacy .env files as archive member names.
##
function backup_collect_legacy_envs() {
    local root cand abs member seen=$'\n'

    root=$(backup_root)

    while IFS= read -r cand; do
        if [[ -z "${cand}" ]]; then
            continue
        fi

        if [[ "${root}" == "/" ]]; then
            abs="${cand}"
        else
            abs="${root}${cand}"
        fi

        if [[ ! -f "${abs}" ]]; then
            continue
        fi

        member=$(backup_member_name "${abs}")

        case "${seen}" in
            *$'\n'"${member}"$'\n'*)
                continue
            ;;
        esac

        seen+="${member}"$'\n'
        printf '%s\n' "${member}"
    done < <(backup_legacy_candidates)
}

##
# Return the SHA-256 checksum of a file.
##
function backup_sha256() {
    local file="${1}"

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${file}" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${file}" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "${file}" | awk '{print $NF}'
    else
        return 1
    fi
}

##
# Check whether an archive member may be restored.
#
# Mirrors the create-time allow-list: system configuration below /etc, the
# LEMPer-provided vsftpd unit, and legacy .env files. Anything else — absolute
# paths, parent traversal, binaries, web roots — is rejected.
##
function backup_member_allowed() {
    local member="${1}"

    if [[ -z "${member}" ]]; then
        return 1
    fi

    if [[ "${member}" == /* ]]; then
        return 1
    fi

    case "/${member}/" in
        *"/../"*)
            return 1
        ;;
    esac

    # Keep restore from reintroducing CLI code or LEMPer's rollback copies.
    case "${member}" in
        etc/lemper/cli-plugins*|etc/lemper/backups*|etc/modsecurity/crs*)
            return 1
        ;;
    esac

    case "${member}" in
        "${LEMPER_BACKUP_MANIFEST}")
            return 0
        ;;
        etc/*)
            return 0
        ;;
        usr/lib/systemd/system/vsftpd.service|lib/systemd/system/vsftpd.service)
            return 0
        ;;
        root/*|opt/*|srv/*|usr/local/*|var/www/*)
            if [[ "${member}" == */.env ]]; then
                return 0
            fi
            return 1
        ;;
    esac

    return 1
}

##
# List archives newest first (timestamped file names sort correctly).
##
function backup_archives() {
    local dir="${1}"
    local file

    if [[ ! -d "${dir}" ]]; then
        return 0
    fi

    for file in "${dir}"/lemper-config-*.tar.gz; do
        if [[ -f "${file}" ]]; then
            printf '%s\n' "${file}"
        fi
    done | LC_ALL=C sort -r
}

##
# Print the newest archive that is not a pre-restore snapshot.
##
function backup_latest_archive() {
    local dir="${1:-${LEMPER_BACKUP_DIR}}"

    backup_archives "${dir}" | grep -v -- '-pre-restore\.tar\.gz$' | head -n 1
}

##
# Resolve an archive argument: a path, "latest", or empty for latest.
##
function backup_resolve_archive() {
    local arg="${1:-}"
    local dir="${2:-${LEMPER_BACKUP_DIR}}"

    if [[ -z "${arg}" || "${arg}" == "latest" ]]; then
        backup_latest_archive "${dir}"
        return 0
    fi

    if [[ -f "${arg}" ]]; then
        printf '%s\n' "${arg}"
    elif [[ -f "${dir}/${arg}" ]]; then
        printf '%s\n' "${dir}/${arg}"
    fi
}

##
# Read one value from an archive manifest.
##
function backup_manifest_value() {
    local key="${1}"
    local file="${2}"

    tar -xzOf "${file}" "${LEMPER_BACKUP_MANIFEST}" 2>/dev/null | \
        awk -F= -v k="${key}" '$1 == k { sub(/^[^=]*=/, ""); print; exit }'
}

##
# Write the manifest for a new archive.
##
function backup_write_manifest() {
    local file="${1}"
    local root="${2}"
    local config_paths="${3}"
    local legacy_paths="${4}"
    local excluded_paths="${5}"

    {
        printf 'FORMAT=%s\n' "${LEMPER_BACKUP_FORMAT}"
        printf 'CREATED_UTC=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'HOSTNAME=%s\n' "$(uname -n)"
        printf 'LEMPER_VERSION=%s\n' "${PROG_VERSION:-unknown}"
        printf 'BACKUP_ROOT=%s\n' "${root}"
        printf 'PATHS=%s\n' "${config_paths}"
        printf 'LEGACY_ENV=%s\n' "${legacy_paths}"
        printf 'EXCLUDED=%s\n' "${excluded_paths}"
    } > "${file}"
}

##
# Create an archive and print its path. Silent on stdout except for the path.
##
function backup_create_archive() {
    local output_dir="${1:-${LEMPER_BACKUP_DIR}}"
    local label="${2:-}"
    local root stamp host archive tmpdir
    local path member
    local config_paths=() legacy_paths=() tar_paths=() excludes=() tar_cmd=()

    root=$(backup_root)
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    host=$(uname -n | tr -cd 'A-Za-z0-9.-')

    if [[ -n "${label}" ]]; then
        label=$(printf '%s' "${label}" | tr -cd 'A-Za-z0-9._-')
    fi

    while IFS= read -r path; do
        if [[ -z "${path}" ]]; then
            continue
        fi

        if [[ -e "${root}/${path}" || -L "${root}/${path}" ]]; then
            config_paths+=("${path}")
        fi
    done < <(backup_path_list)

    while IFS= read -r path; do
        if [[ -n "${path}" ]]; then
            legacy_paths+=("${path}")
        fi
    done < <(backup_collect_legacy_envs)

    tar_paths=("${config_paths[@]}" "${legacy_paths[@]}")

    if [[ ${#tar_paths[@]} -eq 0 ]]; then
        error "No LEMPer configuration found under ${root}."
        return 1
    fi

    if [[ ! -d "${output_dir}" ]]; then
        if ! mkdir -p "${output_dir}"; then
            error "Cannot create backup directory: ${output_dir}"
            return 1
        fi
        chmod 0700 "${output_dir}" 2>/dev/null || true
    fi

    archive="${output_dir}/lemper-config-${host}-${stamp}${label:+-${label}}.tar.gz"

    if [[ -e "${archive}" ]]; then
        archive="${output_dir}/lemper-config-${host}-${stamp}${label:+-${label}}-$$.tar.gz"
    fi

    if [[ "${DRYRUN}" == true ]]; then
        info "Would create ${archive} with ${#tar_paths[@]} members."
        printf '%s\n' "${archive}"
        return 0
    fi

    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/lemper-backup.XXXXXX") || {
        error "Cannot create a temporary directory."
        return 1
    }

    backup_write_manifest "${tmpdir}/${LEMPER_BACKUP_MANIFEST}" "${root}" \
        "${config_paths[*]}" "${legacy_paths[*]}" "${LEMPER_BACKUP_EXCLUDES_DEFAULT[*]}"

    for member in "${LEMPER_BACKUP_EXCLUDES_DEFAULT[@]}"; do
        excludes+=("--exclude=${member}")
    done

    tar_cmd=(tar -czf "${archive}" --numeric-owner)
    tar_cmd+=("${excludes[@]}")
    tar_cmd+=(-C "${root}" "${tar_paths[@]}")
    tar_cmd+=(-C "${tmpdir}" "${LEMPER_BACKUP_MANIFEST}")

    if ! "${tar_cmd[@]}"; then
        rm -f "${archive}"
        rm -rf "${tmpdir}"
        error "Backup archive creation failed."
        return 1
    fi

    rm -rf "${tmpdir}"
    chmod 0600 "${archive}" 2>/dev/null || true

    if ! tar -tzf "${archive}" >/dev/null 2>&1; then
        error "Backup archive failed verification: ${archive}"
        return 1
    fi

    if command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 \
        || command -v openssl >/dev/null 2>&1; then
        backup_sha256 "${archive}" > "${archive}.sha256"
        chmod 0600 "${archive}.sha256" 2>/dev/null || true
    fi

    printf '%s\n' "${archive}"
}

##
# Verify archive integrity and the restore allow-list.
##
function backup_verify_archive() {
    local file="${1}"
    local listing member expected actual
    local bad=()

    if [[ ! -f "${file}" ]]; then
        error "Backup file not found: ${file}"
        return 1
    fi

    if ! gzip -t "${file}" 2>/dev/null; then
        error "Backup archive is not a valid gzip file: ${file}"
        return 1
    fi

    if ! listing=$(tar -tzf "${file}" 2>/dev/null); then
        error "Backup archive cannot be read: ${file}"
        return 1
    fi

    if [[ -z "${listing}" ]]; then
        error "Backup archive is empty: ${file}"
        return 1
    fi

    if ! printf '%s\n' "${listing}" | grep -qx "${LEMPER_BACKUP_MANIFEST}"; then
        error "Backup archive has no ${LEMPER_BACKUP_MANIFEST}."
        return 1
    fi

    while IFS= read -r member; do
        if [[ -z "${member}" || "${member}" == "${LEMPER_BACKUP_MANIFEST}" ]]; then
            continue
        fi

        if ! backup_member_allowed "${member}"; then
            bad+=("${member}")
        fi
    done <<< "${listing}"

    if [[ ${#bad[@]} -gt 0 ]]; then
        error "Archive contains paths LEMPer will not restore: ${bad[*]}"
        return 1
    fi

    if [[ -f "${file}.sha256" ]]; then
        expected=$(awk '{print $1; exit}' "${file}.sha256")
        actual=$(backup_sha256 "${file}" 2>/dev/null || true)

        if [[ -n "${expected}" && -n "${actual}" && "${expected}" != "${actual}" ]]; then
            error "Checksum mismatch for ${file}."
            return 1
        fi
    fi

    return 0
}

##
# Create a configuration backup.
##
function backup_create() {
    local output_dir="${LEMPER_BACKUP_DIR}"
    local label=""
    local archive

    while [[ $# -gt 0 ]]; do
        case "${1}" in
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

    while [[ $# -gt 0 ]]; do
        case "${1}" in
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

    while [[ $# -gt 0 ]]; do
        case "${1}" in
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

    while [[ $# -gt 0 ]]; do
        case "${1}" in
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

    while [[ $# -gt 0 ]]; do
        case "${1}" in
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
            y | Y | yes | YES)
            ;;
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
        "--exclude=etc/lemper/cli-plugins"
        "--exclude=etc/lemper/backups"
    )

    if ! tar -xzf "${file}" -C "${root}" --numeric-owner "${excludes[@]}"; then
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

    while [[ $# -gt 0 ]]; do
        case "${1}" in
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
            y | Y | yes | YES)
            ;;
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
    cat <<- EOL
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
            exit 1
        ;;
    esac
}

# Allow unit tests to source the helpers without running the command.
if [[ "${LEMPER_BACKUP_LIB_ONLY:-false}" != "true" ]]; then
    init_lemper_backup "$@"
fi
