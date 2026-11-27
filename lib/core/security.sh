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


# Pure validation and redaction; sourcing this module never changes the host.
function redact_secrets() {
    local message="$*" name value
    while IFS= read -r name; do
        case "${name}" in
            PASSWORD|PASSWORD_HASH|*_PASSWORD|*_PASSWORD_HASH|*_PASS|*_PASS2|*_TOKEN|*_SECRET|password|pw|secret)
                value="${!name}"
                [[ -n "${value}" ]] && message="${message//"${value}"/[REDACTED]}"
                ;;
        esac
    done < <(compgen -v)
    printf '%s' "${message}"
}

# Apply the site path policy to a canonical path, including a prospective site.
function lemper_webroot_path_allowed() {
    local path="$1" prefix home
    [[ "$path" == /* && "$path" != *$'\n'* && "$path" != *$'\r'* ]] || return 1
    case "$path" in
        /|/home|/srv|/srv/www|/var|/var/www|/opt|/tmp|/var/tmp|/mnt|/media)
            return 1 ;;
        /bin|/bin/*|/boot|/boot/*|/dev|/dev/*|/etc|/etc/*|/lib|/lib/*|/lib32|/lib32/*|\
        /lib64|/lib64/*|/proc|/proc/*|/root|/root/*|/run|/run/*|/sbin|/sbin/*|/sys|/sys/*|/usr|/usr/*)
            return 1 ;;
        /var/*)
            [[ "$path" == /var/www/* ]] || return 1 ;;
    esac
    if [[ "$path" == /home/* ]]; then
        prefix="${path#/home/}"
        home="/home/${prefix%%/*}"
        [[ "$prefix" == */* && "$path" != "$home/webapps" && "$path" != "$home/logs" &&
            "$path" != "$home/.ssh" && "$path" != /home/*/.ssh/* ]] || return 1
    fi
}

# Resolve symlinks and '..' before deciding whether a recursive mutation is safe.
# Application trees may live in /home, /srv, /var/www, /opt, or a custom mount.
function safe_webroot() {
    local target="${1:-}" resolved owner="${2:-}"
    [[ "$target" == /* && -d "$target" && ! -L "$target" ]] || return 1
    [[ "$target" != *$'\n'* && "$target" != *$'\r'* ]] || return 1
    resolved=$(cd -- "$target" && pwd -P) || return 1
    lemper_webroot_path_allowed "$resolved" || return 1
    if [[ -n "${owner}" ]]; then
        if [[ "$(uname -s)" == Darwin ]]; then
            [[ "$(stat -f '%Su' "${resolved}")" == "${owner}" ]] || return 1
        else
            [[ "$(stat -c '%U' "${resolved}")" == "${owner}" ]] || return 1
        fi
    fi
    printf '%s\n' "${resolved}"
}

# All recursive site deletion goes through this boundary.
function delete_site_webroot() {
    local resolved
    resolved=$(safe_webroot "${1:-}" "${2:-}") || {
        error "Refusing unsafe or incorrectly owned website root."
        return 1
    }
    local owner="${2:-}"
    [[ -n "${owner}" ]] || { error "A website owner is required for data removal."; return 1; }
    # Drop privileges for the entire recursive operation. An owner can change
    # writable ancestors after validation, but cannot turn that race into root deletion.
    if command -v runuser >/dev/null 2>&1; then
        run runuser -u "${owner}" -- rm -rf -- "${resolved}"
    elif command -v sudo >/dev/null 2>&1; then
        run sudo -u "${owner}" -- rm -rf -- "${resolved}"
    else
        error "runuser or sudo is required to remove website data safely."
        return 1
    fi
}

function is_valid_username() {
    [[ "${1:-}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

function is_valid_domain() {
    local domain="${1:-}"
    [[ ${#domain} -ge 4 && ${#domain} -le 253 ]] &&
        [[ "${domain}" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$ ]]
}

# Replace the pathname atomically, never write through a versioned CLI symlink.
function install_cli_binary() {
    local source="${1}" destination="${2}" temporary
    [[ -f "${source}" ]] || return 1
    [[ "${DRYRUN:-false}" != true ]] || { info "Would install CLI binary."; return 0; }
    temporary=$(mktemp "${destination}.XXXXXX") || return 1
    if ! install -m 0755 "${source}" "${temporary}" || ! mv -f "${temporary}" "${destination}"; then
        rm -f "${temporary}"
        return 1
    fi
}

# Every writable directory and ancestor must be trusted; root-owned sticky /tmp is allowed.
function lemper_directory_trusted() {
    local directory="$1" cursor owner mode
    [[ "$directory" == /* && "$(realpath -ms -- "$directory")" == "$directory" ]] || return 1
    cursor="$directory"
    while [[ "$cursor" != / ]]; do
        if [[ -e "$cursor" || -L "$cursor" ]]; then
            [[ -d "$cursor" && ! -L "$cursor" ]] || return 1
            read -r owner mode < <(stat -c '%u %a' -- "$cursor") || return 1
            [[ "$owner" == "$EUID" || "$owner" == 0 ]] || return 1
            if (( (8#$mode & 0022) != 0 )); then
                [[ "$owner" == 0 && ( "$cursor" == /tmp || "$cursor" == /var/tmp ) ]] &&
                    (( (8#$mode & 01000) != 0 )) || return 1
            fi
        fi
        cursor="${cursor%/*}"
        [[ -n "$cursor" ]] || cursor=/
    done
}

# A deployed release contains ordinary single-link files and one fixed compatibility link.
function lemper_release_tree_trusted() {
    local release="$1" unsafe
    [[ -d "$release" && -f "$release/lib/core/registry.sh" && -f "$release/bin/lemper-cli.sh" ]] || return 1
    lemper_directory_trusted "$release" || return 1
    unsafe=$(find "$release" \( ! -uid "$EUID" -o \( ! -type l -perm /022 \) -o \( -type f -links +1 \) -o \
        ! \( -type d -o -type f -o \( -type l -path "$release/scripts/lemper_stacks.sh" -lname '../lib/core/lemper-stacks.sh' \) \) \) -printf x -quit) || return 1
    [[ -z "$unsafe" ]]
}

# Pin the trusted version directory. A missing selector is distinct from an unsafe selector.
function lemper_installed_release() {
    local installation="${1:-/opt/lemper}" selector target name
    selector="$installation/current"
    lemper_directory_trusted "$installation" || return 1
    [[ -e "$selector" || -L "$selector" ]] || return 2
    [[ -L "$selector" && "$(stat -c %u -- "$selector")" == "$EUID" ]] || return 1
    target=$(readlink -- "$selector") || return 1
    name=${target#"$installation/"}
    [[ "$name" =~ ^([0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?|local-[A-Za-z0-9]+)$ ]] || return 1
    target="$installation/$name"
    [[ "$selector" -ef "$target" ]] && lemper_release_tree_trusted "$target" || return 1
    printf '%s\n' "$target"
}

# Create a private workspace beneath a protected parent. Never adopt an old shared build tree.
function lemper_build_workspace() {
    local path="$1" parent
    parent=$(dirname -- "$path") || return 1
    lemper_directory_trusted "$parent" && [[ -d "$parent" ]] || return 1
    [[ "$path" != "$parent" && "$path" != *$'\n'* && "$path" != *$'\r'* &&
        "$path" == "$(realpath -ms -- "$path")" ]] || return 1
    if [[ ! -d "$path" ]]; then
        lemper_exec mkdir -m 0700 -- "$path" || return 1
        [[ "${DRYRUN:-false}" != true ]] || return 0
        lemper_exec install -m 0600 /dev/null "$path/.lemper-build-workspace" || return 1
    fi
    lemper_directory_trusted "$path" && [[ "$(stat -c %a -- "$path")" == 700 ]] || {
        error "Build workspace must be a private directory owned by the installer."
        return 1
    }
}

function lemper_remove_build_workspace() {
    local path="$1" marker="$1/.lemper-build-workspace"
    [[ -f "$marker" && ! -L "$marker" ]] || return 0
    lemper_directory_trusted "$path" &&
        [[ "$(stat -c %a -- "$path")" == 700 && "$(stat -c '%u:%a:%h' -- "$marker")" == "$EUID:600:1" ]] || return 1
    lemper_exec rm -rf -- "$path"
}

# Legacy releases assigned these files to the web worker. Their contents cannot
# be used for a privileged refresh, even after changing ownership retrospectively.
function lemper_web_tools_tree_safe() {
    local directory="${1:-/usr/share/nginx/html}" unsafe
    lemper_directory_trusted "$directory" || { error "Migrate the legacy web-owned Nginx document tree before refreshing tools."; return 1; }
    [[ -d "$directory" ]] || return 0
    unsafe=$(find "$directory" \( ! -uid 0 -o \( ! -type l -perm /022 \) -o ! \( -type d -o -type f -o -type l \) -o \( -type f -links +1 \) \) -printf x -quit) || return 1
    [[ -z "$unsafe" ]] || { error "Web tools require a clean, root-owned document tree. See the security migration guide."; return 1; }
    # Composer can install relative links to other files in this protected tree.
    find "$directory" -type l -exec bash -c '
        root=$1
        shift
        for link do
            target=$(readlink -- "$link") && [[ "$target" != /* ]] || exit 1
            base=${link%/*}
            while [[ "$target" == ../* ]]; do
                [[ "$base" != "$root" ]] || exit 1
                base=${base%/*}
                target=${target#../}
            done
            [[ "/$target/" != */../* ]] || exit 1
            resolved=$(realpath -e -- "$link") && [[ "$resolved" == "$root/"* &&
                "$resolved" == "$(realpath -ms -- "$base/$target")" ]] || exit 1
        done
    ' _ "$directory" {} +
}
