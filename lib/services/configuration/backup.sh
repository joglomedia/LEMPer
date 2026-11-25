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
    local candidate

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
        etc/lemper/core* | etc/lemper/runtime* | etc/lemper/services* | etc/lemper/compat* | etc/lemper/cli-plugins* | etc/lemper/backups* | etc/modsecurity/crs*)
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
        usr/lib/systemd/system/vsftpd.service | lib/systemd/system/vsftpd.service)
            return 0
            ;;
        root/* | opt/* | srv/* | usr/local/* | var/www/*)
            if [[ "${member}" == */.env ]]; then
                return 0
            fi
            return 1
            ;;
    esac

    # Custom checkout locations come from local installer state or an explicit
    # operator override, never from the archive's untrusted manifest. Permit
    # only that exact legacy file, preserving the traversal/code checks above.
    if [[ "${member}" == */.env ]]; then
        while IFS= read -r candidate; do
            [[ "${candidate}" == /* ]] || continue
            if [[ "${member}" == "${candidate#/}" ]]; then
                return 0
            fi
        done < <(backup_legacy_candidates)
    fi

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

    tar -xzOf "${file}" "${LEMPER_BACKUP_MANIFEST}" 2>/dev/null \
        | awk -F= -v k="${key}" '$1 == k { sub(/^[^=]*=/, ""); print; exit }'
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
    } >"${file}"
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
        backup_sha256 "${archive}" >"${archive}.sha256"
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
    done <<<"${listing}"

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
