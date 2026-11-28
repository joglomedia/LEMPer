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
# Mirrors the create-time allow-list: selected configuration below /etc, the
# LEMPer-provided vsftpd unit, and legacy .env files. Anything else — absolute
# paths, parent traversal, binaries, web roots — is rejected.
##
function backup_member_allowed() {
    local member="${1%/}"
    local candidate
    shift

    if [[ -z "${member}" ]]; then
        return 1
    fi

    if [[ "${member}" == /* ]]; then
        return 1
    fi

    case "/${member}/" in
        *"/../"* | *"/./"* | *"//"*)
            return 1
            ;;
    esac

    # Keep restore from reintroducing CLI code or LEMPer's rollback copies.
    case "${member}" in
        etc/lemper/core* | etc/lemper/runtime* | etc/lemper/services* | etc/lemper/compat* | etc/lemper/cli-plugins* | etc/lemper/backups* | \
            etc/lemper-mail/.lemper-restore.* | etc/modsecurity/crs*)
            return 1
            ;;
    esac

    [[ "$member" == "$LEMPER_BACKUP_MANIFEST" ]] && return 0
    [[ "$member" == lib/systemd/system/vsftpd.service ]] && return 0
    if [[ $# -eq 0 ]]; then
        local -a paths
        mapfile -t paths < <(backup_path_list)
        set -- "${paths[@]}"
    fi
    for candidate; do
        [[ "$member" == "$candidate" || "$member" == "$candidate/"* ]] && return 0
    done

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
# Permit links into managed configuration and the package links used by supported distributions.
##
function backup_symlink_allowed() {
    local member="$1" target="$2" resolved
    [[ -n "$target" && "$target" != *[[:cntrl:]\\]* ]] || return 1
    [[ "$target" == /* ]] || target="/${member%/*}/$target"
    resolved=$(realpath -ms -- "$target") || return 1
    if [[ "$member" =~ ^etc/postgresql/([0-9]+([.][0-9]+)?)/([A-Za-z0-9_][A-Za-z0-9_-]*)/log$ ]]; then
        [[ "$resolved" == "/var/log/postgresql/postgresql-${BASH_REMATCH[1]}-${BASH_REMATCH[3]}.log" ]] && return 0
    fi

    case "$member:$resolved" in
        etc/nginx/modules-enabled/*:/usr/share/nginx/modules-available/* | \
            etc/mysql/my.cnf:/etc/alternatives/my.cnf | \
            etc/postfix/makedefs.out:/usr/share/postfix/makedefs.out | \
            etc/dovecot/private/dovecot.key:/etc/ssl/private/ssl-cert-snakeoil.key | \
            etc/dovecot/private/dovecot.pem:/etc/ssl/certs/ssl-cert-snakeoil.pem | \
            etc/systemd/system/pure-ftpd.service:/usr/lib/systemd/system/pure-ftpd.service | \
            etc/systemd/system/pure-ftpd.service:/lib/systemd/system/pure-ftpd.service)
            return 0
            ;;
    esac
    [[ "$resolved" != "/$LEMPER_BACKUP_MANIFEST" ]] && backup_member_allowed "${resolved#/}"
}

##
# Validate archive member names and types together. Restore must not write
# through a pre-existing link or an ancestor a lower-trust account can replace.
##
function backup_verify_members() {
    local file="$1" restore_root="${2:-}" listing details
    local member entry type name target parent destination index tree live_tree
    local -a members entries paths
    local -A member_types=() protected_parents=()

    listing=$(LC_ALL=C tar --quoting-style=escape -tzf "$file") || return 1
    details=$(LC_ALL=C tar --quoting-style=escape --numeric-owner -tvzf "$file") || return 1
    if ! grep -Fxq -- "$LEMPER_BACKUP_MANIFEST" <<<"$listing"; then
        error "Backup archive has no ${LEMPER_BACKUP_MANIFEST}."
        return 1
    fi
    mapfile -t members <<<"$listing"
    mapfile -t entries <<<"$details"
    mapfile -t paths < <(backup_path_list)
    [[ ${#members[@]} -eq ${#entries[@]} ]] || return 1

    for index in "${!members[@]}"; do
        name="${members[index]}"
        member="${name%/}"
        if [[ "$name" == *[[:cntrl:]\\]* ]] || ! backup_member_allowed "$name" "${paths[@]}"; then
            error "Archive contains a path LEMPer will not restore."
            return 1
        fi
        entry="${entries[index]}"
        read -r type _ _ _ _ target <<<"$entry"
        case "${type:0:1}" in
            - | d) ;;
            l)
                if [[ "$member" == etc/knot/lemper/* || "$member" == etc/lemper/dns-keys/* || "$target" != "$name -> "* ]] \
                    || ! backup_symlink_allowed "$member" "${target#"$name -> "}"; then
                    error "Archive contains a symbolic link outside the managed configuration."
                    return 1
                fi
                ;;
            h)
                # Format 1 could add a legacy .env twice, resulting in a
                # regular file followed by a hard-link entry to itself.
                if [[ "$member" == */.env && "${member_types[$member]:-}" == - &&
                    "$target" == "$name link to $name" ]]; then
                    continue
                fi
                error "Archive contains an unsupported hard link."
                return 1
                ;;
            *)
                error "Unsupported configuration archive member type."
                return 1
                ;;
        esac
        if [[ -n "${member_types[$member]:-}" || ("$member" == "$LEMPER_BACKUP_MANIFEST" && "${type:0:1}" != -) ]]; then
            error "Archive contains a duplicate member or an invalid manifest."
            return 1
        fi
        member_types["$member"]="${type:0:1}"
    done

    for member in "${!member_types[@]}"; do
        [[ "$member" != "$LEMPER_BACKUP_MANIFEST" ]] || continue
        parent=$(dirname -- "/$member") || return 1
        if [[ -n "$restore_root" ]]; then
            destination="${restore_root%/}$parent"
            for tree in "${LEMPER_BACKUP_RESTORE_TREES[@]}"; do
                [[ "$member" == "$tree" || "$member" == "$tree/"* ]] || continue
                if [[ "${member_types[$tree]:-}" != d ]]; then
                    error "Restore requires a complete managed service directory."
                    return 1
                fi
                live_tree="${restore_root%/}/$tree"
                if [[ "$member" == "$tree" && (-L "$live_tree" || (-e "$live_tree" && ! -d "$live_tree")) ]]; then
                    error "Restore requires a real destination directory for managed service state."
                    return 1
                fi
                destination="${restore_root%/}/${tree%/*}"
                break
            done
            # On usrmerged systems the historical path is a system alias.
            if [[ "$member" == lib/systemd/system/vsftpd.service &&
                "$(readlink -- "${restore_root%/}/lib")" == usr/lib ]]; then
                destination="${restore_root%/}/usr$parent"
            fi
            if [[ -z "${protected_parents[$destination]:-}" ]]; then
                if ! lemper_directory_trusted "$destination"; then
                    error "Restore requires protected configuration directories."
                    return 1
                fi
                protected_parents["$destination"]=1
            fi
        fi
        while [[ "$parent" != / ]]; do
            if [[ -n "${member_types[${parent#/}]:-}" && "${member_types[${parent#/}]}" != d ]]; then
                error "Archive path has a non-directory ancestor."
                return 1
            fi
            parent="${parent%/*}"
            [[ -n "$parent" ]] || parent=/
        done
    done
}

# Restore service-owned directories from protected staging outside the live
# tree. The final rename operates only in a root-controlled parent.
function backup_publish_restore_tree() (
    local source="$1" destination="$2" parent="${2%/*}" temporary
    lemper_directory_trusted "$parent" && [[ -d "$parent" && ! -L "$destination" ]] || return 1
    [[ ! -e "$destination" || -d "$destination" ]] || return 1
    temporary=$(mktemp -d "$parent/.lemper-restore.XXXXXXXX") || return 1
    trap 'if [[ ! -e "$temporary/previous" ]]; then rm -rf -- "$temporary"; fi' EXIT
    cp -a -- "$source" "$temporary/new" || return 1
    if [[ -d "$destination" ]]; then
        mv -T -- "$destination" "$temporary/previous" || return 1
    fi
    if ! mv -T -- "$temporary/new" "$destination"; then
        if [[ -d "$temporary/previous" ]] && ! mv -T -- "$temporary/previous" "$destination"; then
            error "Previous service configuration remains at $temporary/previous."
        fi
        return 1
    fi
    if ! rm -rf --one-file-system -- "$temporary/previous"; then
        warning "Previous service configuration remains at $temporary/previous."
    fi
)

# The caller passes previously verified bytes and a private workspace. Only
# the managed service directories need wholesale publication. Other paths
# retain the existing overlay semantics.
function backup_apply_restore() {
    local file="$1" root="$2" stage="$3" listing member tree
    local -a excludes=("--exclude=$LEMPER_BACKUP_MANIFEST") trees=()
    for member in "${LEMPER_BACKUP_EXCLUDES_DEFAULT[@]}"; do
        excludes+=("--exclude=$member")
    done
    listing=$(LC_ALL=C tar --quoting-style=escape -tzf "$file") || return 1
    for tree in "${LEMPER_BACKUP_RESTORE_TREES[@]}"; do
        if grep -Fxq -e "$tree" -e "$tree/" <<<"$listing"; then
            trees+=("$tree")
            excludes+=("--exclude=$tree")
        fi
    done
    if [[ ${#trees[@]} -gt 0 ]]; then
        mkdir -m 0700 -- "$stage" || return 1
        tar -xzf "$file" -C "$stage" --numeric-owner --delay-directory-restore -- "${trees[@]}" || return 1
        # Knot only reads these root-owned regular files/directories. Distribution
        # package group IDs may differ between the original and recovery hosts.
        if [[ "$root" == / && -d "$stage/etc/knot/lemper" ]]; then
            chown -Rh root:knot -- "$stage/etc/knot/lemper" || return 1
        fi
    fi
    if ! (
        set -o pipefail
        lemper_transfer_read "$file" | tar -xz -C "$root" --numeric-owner --delay-directory-restore "${excludes[@]}"
    ); then
        return 1
    fi
    for tree in "${trees[@]}"; do
        backup_publish_restore_tree "$stage/$tree" "${root%/}/$tree" || return 1
    done
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
function backup_create_archive() (
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

    tar_paths=("${config_paths[@]}")
    for member in "${legacy_paths[@]}"; do
        for path in "${config_paths[@]}"; do
            [[ "$member" != "$path" && "$member" != "$path/"* ]] || continue 2
        done
        tar_paths+=("$member")
    done

    if [[ ${#tar_paths[@]} -eq 0 ]]; then
        error "No LEMPer configuration found under ${root}."
        return 1
    fi

    output_dir=$(realpath -ms -- "$output_dir") || return 1
    lemper_directory_trusted "$output_dir" || {
        error "Untrusted backup directory."
        return 1
    }
    umask 077
    archive="${output_dir}/lemper-config-${host}-${stamp}${label:+-${label}}.tar.gz"

    if [[ -e "$archive" || -L "$archive" || -e "$archive.sha256" || -L "$archive.sha256" ]]; then
        archive="${output_dir}/lemper-config-${host}-${stamp}-${BASHPID}${label:+-${label}}.tar.gz"
    fi

    if [[ "${DRYRUN}" == true ]]; then
        info "Would create ${archive} with ${#tar_paths[@]} members."
        printf '%s\n' "${archive}"
        return 0
    fi

    if [[ ! -d "$output_dir" ]]; then
        mkdir -p -- "$output_dir" || return 1
        lemper_directory_trusted "$output_dir" && chmod 0700 -- "$output_dir" || return 1
    fi
    tmpdir=$(mktemp -d "$output_dir/.lemper-backup.XXXXXXXX") || {
        error "Cannot create a temporary directory."
        return 1
    }

    trap 'rm -rf -- "$tmpdir"' EXIT
    backup_write_manifest "${tmpdir}/${LEMPER_BACKUP_MANIFEST}" "${root}" \
        "${config_paths[*]}" "${legacy_paths[*]}" "${LEMPER_BACKUP_EXCLUDES_DEFAULT[*]}" || return 1

    for member in "${LEMPER_BACKUP_EXCLUDES_DEFAULT[@]}"; do
        excludes+=("--exclude=${member}")
    done

    tar_cmd=(tar -czf "$tmpdir/archive" --numeric-owner --hard-dereference)
    tar_cmd+=("${excludes[@]}")
    tar_cmd+=(-C "${root}" "${tar_paths[@]}")
    tar_cmd+=(-C "${tmpdir}" "${LEMPER_BACKUP_MANIFEST}")

    "${tar_cmd[@]}" && backup_verify_members "$tmpdir/archive" || return 1
    local digest
    digest=$(backup_sha256 "$tmpdir/archive") && [[ "$digest" =~ ^[a-f0-9]{64}$ ]] || return 1
    printf '%s\n' "$digest" >"$tmpdir/checksum" || return 1
    chmod 0600 -- "$tmpdir/archive" "$tmpdir/checksum" || return 1
    ln -T -- "$tmpdir/checksum" "$archive.sha256" || return 1
    if ! ln -T -- "$tmpdir/archive" "$archive"; then
        rm -f -- "$archive.sha256"
        return 1
    fi

    printf '%s\n' "${archive}"
)

##
# Verify archive integrity and the restore allow-list.
##
function backup_verify_archive() {
    local file="${1}"
    local restore_root="${2:-}" expected actual

    if [[ ! -f "${file}" ]]; then
        error "Backup file not found: ${file}"
        return 1
    fi

    if ! gzip -t "${file}" 2>/dev/null; then
        error "Backup archive is not a valid gzip file: ${file}"
        return 1
    fi

    backup_verify_members "$file" "$restore_root" || return 1

    if [[ -f "${file}.sha256" ]]; then
        expected=$(awk '{print $1; exit}' "${file}.sha256")
        actual=$(backup_sha256 "${file}" 2>/dev/null || true)

        if [[ ! "$expected" =~ ^[a-fA-F0-9]{64}$ || "${expected,,}" != "$actual" ]]; then
            error "Checksum mismatch for ${file}."
            return 1
        fi
    fi

    return 0
}

# A checksum provided beside an archive is an integrity check. Only files
# controlled by the local administrator can cross the privileged restore boundary.
function backup_artifact_trusted() {
    local file="$1" parent owner mode
    [[ -f "$file" && ! -L "$file" ]] || return 1
    parent="${file%/*}"
    lemper_directory_trusted "${parent:-/}" || return 1
    read -r owner mode < <(stat -c '%u %a' -- "$file") || return 1
    [[ "$owner" == "$EUID" && "$mode" =~ ^[0-7]{1,4}$ ]] && (((8#$mode & 0022) == 0))
}
