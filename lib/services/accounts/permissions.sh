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

# Create only the requested directory as root when its parent is protected.
# Any directory creation through a tenant-writable path runs as the tenant.
function lemper_site_prepare_directory() {
    local target="$1" owner="$2" mode="$3" resolved parent ancestor uid gid index
    local -a missing=()
    is_valid_username "$owner" && uid=$(id -u "$owner") && [[ "$uid" != 0 ]] || return 1
    [[ "$target" == /* && "$target" == "$(realpath -ms -- "$target")" ]] || return 1
    lemper_webroot_path_allowed "$target" || return 1
    resolved=$(realpath -m -- "$target") || return 1
    lemper_webroot_path_allowed "$resolved" || return 1
    if [[ -e "$target" || -L "$target" ]]; then
        safe_webroot "$target" "$owner" >/dev/null
        return
    fi
    if [[ "${DRYRUN:-false}" == true ]]; then
        run runuser -u "$owner" -- mkdir -p -m "$mode" -- "$target"
        return
    fi
    if ! runuser -u "$owner" -- mkdir -p -m "$mode" -- "$target" 2>/dev/null; then
        parent=$(dirname -- "$target") || return 1
        ancestor="$parent"
        while [[ ! -e "$ancestor" && ! -L "$ancestor" ]]; do
            missing+=("$ancestor")
            ancestor="${ancestor%/*}"
            [[ -n "$ancestor" ]] || ancestor=/
        done
        lemper_directory_trusted "$ancestor" || return 1
        gid=$(id -g "$owner") || return 1
        # Do not adopt an ancestor that another user creates concurrently.
        for ((index = ${#missing[@]} - 1; index >= 0; index--)); do
            mkdir -m 0755 -- "${missing[index]}" || return 1
        done
        mkdir -m "$mode" -- "$target" || return 1
        chown -h -- "$uid:$gid" "$target" || return 1
    fi
    safe_webroot "$target" "$owner" >/dev/null
}

# Apply modes with the site's privileges, including when its parent is mutable.
function fixpermission() {
    local target="${1:-}" owner="${2:-}" resolved uid
    if [[ -n "$target" && "$target" != /* ]]; then
        target="$(pwd -P)/$target"
    fi
    resolved=$(safe_webroot "$target") || {
        error "Refusing to change permissions on $target."
        return 1
    }
    [[ -n "$owner" ]] || owner=$(stat -c %U -- "$resolved") || return 1
    is_valid_username "$owner" && uid=$(id -u "$owner") && [[ "$uid" != 0 && "$(stat -c %u -- "$resolved")" == "$uid" ]] || {
        error "Refusing to change permissions outside a non-root site owner's directory."
        return 1
    }
    # Let find execute chmod directly; symlink or rename races retain tenant privileges.
    run runuser -u "$owner" -- find "$resolved" -xdev -user "$uid" \
        \( -type d -exec chmod 0755 -- {} \; -o \
        -type f \( \( -name wp-config.php -o -name .env -o -name '.env.*' \) -exec chmod go-rwx -- {} + -o \
        ! -name wp-config.php ! -name .env ! -name '.env.*' -exec chmod 0644 -- {} + \) \) || return 1
    success "Permissions fixed for $resolved."
}
