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

# State is root-only data, never executable configuration.
function lemper_hosting_root() {
    local root="${LEMPER_HOSTING_ROOT:-/etc/lemper/hosting}" parent
    [[ "$root" =~ ^/[a-zA-Z0-9_./-]+$ && "$root" != *..* ]] || return 1
    parent="$root"
    while [[ "$parent" != / ]]; do
        [[ ! -L "$parent" ]] || {
            error "Refusing symlink hosting state."
            return 1
        }
        parent="${parent%/*}"
        [[ -n "$parent" ]] || parent=/
    done
    printf '%s\n' "$root"
}
function lemper_hosting_name() { [[ "${1:-}" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]; }
function lemper_hosting_number() { [[ "${1:-}" =~ ^(0|[1-9][0-9]{0,11})$ ]]; }
function lemper_hosting_limits() {
    [[ $# == 4 ]] || return 1
    local value
    for value in "$@"; do lemper_hosting_number "$value" || return 1; done
    (($2 > 0 && $4 > 0 && $1 <= $2 && $3 <= $4)) || {
        error "Disk and inode hard limits must be positive; soft limits cannot exceed hard limits."
        return 1
    }
}
# Sizes are binary KiB; bare numbers mean KiB, M/G/T are binary multiples.
function lemper_hosting_size() {
    local value="$1" number unit multiplier=1
    [[ "$value" =~ ^([0-9]{1,9})([KkMmGgTt]?)$ ]] || return 1
    number="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]}"
    case "$unit" in M | m) multiplier=1024 ;; G | g) multiplier=1048576 ;; T | t) multiplier=1073741824 ;; esac
    value=$((10#$number * multiplier))
    lemper_hosting_number "$value" || return 1
    printf '%s\n' "$value"
}
function lemper_hosting_plan_read() {
    local name="$1" root row
    lemper_hosting_name "$name" || return 1
    root=$(lemper_hosting_root) || return 1
    [[ -f "$root/plans/$name.conf" && ! -L "$root/plans" && ! -L "$root/plans/$name.conf" ]] || {
        error "Hosting plan does not exist."
        return 1
    }
    row=$(cat "$root/plans/$name.conf") || return 1
    [[ "$row" =~ ^[0-9]+\ [0-9]+\ [0-9]+\ [0-9]+$ ]] || return 1
    local limits=()
    read -r -a limits <<<"$row"
    lemper_hosting_limits "${limits[@]}" || return 1
    printf '%s\n' "$row"
}
function lemper_hosting_state_read() {
    local user="$1" root row
    is_valid_username "$user" && [[ "$user" != root ]] || return 1
    root=$(lemper_hosting_root) || return 1
    [[ ! -L "$root/assignments" && -f "$root/assignments/$user.conf" && ! -L "$root/assignments/$user.conf" ]] || return 1
    row=$(cat "$root/assignments/$user.conf") || return 1
    # schema, plan, UID, mount, filesystem UUID, original/prior/next limits, phase.
    read -r -a LEMPER_HOSTING_STATE <<<"$row"
    [[ ${#LEMPER_HOSTING_STATE[@]} == 18 && "$row" != *$'\n'* && "${LEMPER_HOSTING_STATE[0]}" == 1 ]] || return 1
    lemper_hosting_name "${LEMPER_HOSTING_STATE[1]}" || return 1
    local index
    for index in 2 5 6 7 8 9 10 11 12 13 14 15 16; do
        lemper_hosting_number "${LEMPER_HOSTING_STATE[index]}" || return 1
    done
    [[ "${LEMPER_HOSTING_STATE[3]}" =~ ^/[a-zA-Z0-9_./-]*$ && "${LEMPER_HOSTING_STATE[3]}" != *..* &&
        "${LEMPER_HOSTING_STATE[4]}" =~ ^[a-fA-F0-9-]{36}$ && "${LEMPER_HOSTING_STATE[17]}" =~ ^(active|pending)$ ]] || return 1
}
function lemper_hosting_write() {
    local file="$1" row="$2" temporary
    [[ ! -L "${file%/*}" && ! -L "$file" ]] || return 1
    lemper_exec install -d -m0700 "${file%/*}" || return 1
    temporary=$(mktemp "${file%/*}/.hosting.XXXXXXXX") || return 1
    if ! printf '%s\n' "$row" >"$temporary" || ! chmod 0600 "$temporary" || ! mv -Tf "$temporary" "$file"; then
        rm -f "$temporary"
        return 1
    fi
}
function lemper_hosting_plan_used() {
    local name="$1" root file
    root=$(lemper_hosting_root) || return 0
    [[ ! -L "$root/assignments" ]] || return 0
    for file in "$root"/assignments/*.conf; do
        [[ -e "$file" || -L "$file" ]] || continue
        # Invalid state blocks plan deletion/updates conservatively.
        lemper_hosting_state_read "$(basename "$file" .conf)" || return 0
        [[ "${LEMPER_HOSTING_STATE[1]}" != "$name" ]] || return 0
    done
    return 1
}
function lemper_hosting_plan_put() {
    local name="$1" root row
    shift
    lemper_hosting_name "$name" && lemper_hosting_limits "$@" || return 1
    root=$(lemper_hosting_root) || return 1
    if [[ -e "$root/plans/$name.conf" ]]; then
        row=$(lemper_hosting_plan_read "$name") || return 1
        [[ "$row" != "$*" ]] || return 0
        ! lemper_hosting_plan_used "$name" || {
            error "Plan is assigned; create a new plan and reassign accounts to upgrade."
            return 1
        }
    fi
    [[ "${DRYRUN:-false}" != true ]] || {
        info "Would save hosting plan $name."
        return 0
    }
    lemper_hosting_write "$root/plans/$name.conf" "$*"
}
function lemper_hosting_plan_delete() {
    local name="$1" root
    lemper_hosting_plan_read "$name" >/dev/null || return 1
    ! lemper_hosting_plan_used "$name" || {
        error "Detach all accounts before deleting this plan."
        return 1
    }
    root=$(lemper_hosting_root) || return 1
    lemper_exec rm -f "$root/plans/$name.conf"
}
function lemper_hosting_user() {
    local user="$1" mount="$2" root uid home actual
    is_valid_username "$user" && [[ "$user" != root ]] || return 1
    root="${LEMPER_HOSTING_ACCOUNT_ROOT:-/etc/lemper/accounts}"
    [[ -f "$root/$user.conf" && ! -L "$root/$user.conf" ]] || {
        error "Account must be provisioned by lemperctl account before assigning a plan."
        return 1
    }
    uid=$(id -u "$user") || return 1
    if [[ ! "$uid" =~ ^[0-9]+$ ]] || ((uid < 1000 || uid == 65534)); then
        error "Refusing quotas for system accounts."
        return 1
    fi
    home=$(getent passwd "$user" | cut -d: -f6) || return 1
    home=$(realpath -e -- "$home") || return 1
    actual=$(findmnt -rn -T "$home" -o TARGET) || return 1
    [[ "$actual" == "$mount" ]] || {
        error "Account home is not on the selected quota filesystem."
        return 1
    }
    printf '%s\n' "$uid"
}
function lemper_hosting_preflight() {
    local plan="$1" mount="${HOSTING_QUOTA_MOUNT:-/home}" actual
    lemper_hosting_plan_read "$plan" >/dev/null || return 1
    lemper_quota_mount "$mount" >/dev/null || return 1
    actual=$(findmnt -rn -T /home -o TARGET) || return 1
    [[ "$actual" == "$mount" ]] || {
        error "New hosting accounts use /home; it must be on HOSTING_QUOTA_MOUNT."
        return 1
    }
}
function lemper_hosting_assign() {
    local user="$1" plan="$2" root mount="${HOSTING_QUOTA_MOUNT:-/home}" uid uuid row report used files
    local limits=() original=() previous=() current=() record=()
    root=$(lemper_hosting_root) || return 1
    row=$(lemper_hosting_plan_read "$plan") || return 1
    read -r -a limits <<<"$row"
    uuid=$(lemper_quota_mount "$mount") || return 1
    uid=$(lemper_hosting_user "$user" "$mount") || return 1
    report=$(lemper_quota_read "$uid" "$mount") || return 1
    local values=()
    read -r -a values <<<"$report"
    used="${values[0]}"
    files="${values[1]}"
    current=("${values[@]:2:4}")
    local value
    for value in "${current[@]}"; do lemper_hosting_number "$value" || {
        error "Existing quota exceeds the supported plan range."
        return 1
    }; done
    original=("${current[@]}")
    previous=("${current[@]}")
    if [[ -e "$root/assignments/$user.conf" ]]; then
        lemper_hosting_state_read "$user" || return 1
        record=("${LEMPER_HOSTING_STATE[@]}")
        [[ "${record[2]}" == "$uid" && "${record[3]}" == "$mount" && "${record[4]}" == "$uuid" && "${record[17]}" == active ]] || {
            error "Assignment identity changed or recovery is pending. Detach/recover before migrating."
            return 1
        }
        [[ "${record[*]:13:4}" == "${current[*]}" ]] || {
            error "Quota limits changed outside LEMPer; reconcile them before reassigning."
            return 1
        }
        original=("${record[@]:5:4}")
        if [[ "${record[1]}" == "$plan" && "${current[*]}" == "${limits[*]}" ]]; then return 0; fi
    fi
    ((used <= limits[1] && files <= limits[3])) || {
        error "Current usage exceeds the new hard limits; free space/inodes before downgrading."
        return 1
    }
    [[ "${DRYRUN:-false}" != true ]] || {
        info "Would assign $plan to $user on $mount."
        return 0
    }
    local pending="1 $plan $uid $mount $uuid ${original[*]} ${previous[*]} ${limits[*]} pending"
    lemper_hosting_write "$root/assignments/$user.conf" "$pending" || return 1
    if ! lemper_quota_set "$uid" "$mount" "${limits[@]}"; then
        if lemper_quota_set "$uid" "$mount" "${previous[@]}"; then
            if [[ ${#record[@]} == 0 ]]; then rm -f "$root/assignments/$user.conf"; else lemper_hosting_write "$root/assignments/$user.conf" "${record[*]}"; fi
        fi
        error "Quota assignment failed; check hosting status and recover any pending transaction."
        return 1
    fi
    lemper_hosting_write "$root/assignments/$user.conf" "${pending%pending}active" || {
        error "Quota applied; transaction remains pending. Use hosting recover."
        return 1
    }
    info "Assigned $plan to $user; disk and inode hard limits are enforced."
}
function lemper_hosting_detach() {
    local user="$1" recovery="${2:-false}" root uid uuid mount report current=() limits=()
    root=$(lemper_hosting_root) || return 1
    lemper_hosting_state_read "$user" || return 1
    local record=("${LEMPER_HOSTING_STATE[@]}")
    mount="${record[3]}"
    uid=$(lemper_hosting_user "$user" "$mount") || return 1
    uuid=$(lemper_quota_mount "$mount") || return 1
    [[ "$uid" == "${record[2]}" && "$uuid" == "${record[4]}" ]] || {
        error "Account/filesystem identity changed; refusing quota removal."
        return 1
    }
    report=$(lemper_quota_read "$uid" "$mount") || return 1
    local values=()
    read -r -a values <<<"$report"
    current=("${values[@]:2:4}")
    if [[ "$recovery" == true ]]; then
        [[ "${record[17]}" == pending ]] || {
            error "No pending transaction."
            return 1
        }
        limits=("${record[@]:5:4}")
    else
        [[ "${record[17]}" == active ]] || {
            error "Recover the pending assignment first."
            return 1
        }
        [[ "${current[*]}" == "${record[*]:13:4}" || "${current[*]}" == "${record[*]:5:4}" ]] || {
            error "Externally changed quotas; refusing to overwrite them."
            return 1
        }
        limits=("${record[@]:5:4}")
    fi
    # A crash may occur before or after setquota; both states are recoverable.
    if [[ "$recovery" == true && "${current[*]}" != "${record[*]:13:4}" && "${current[*]}" != "${record[*]:9:4}" && "${current[*]}" != "${record[*]:5:4}" ]]; then
        error "Externally changed quotas; manual reconciliation required."
        return 1
    fi
    lemper_quota_set "$uid" "$mount" "${limits[@]}" || return 1
    [[ "${DRYRUN:-false}" != true ]] || return 0
    lemper_exec rm -f "$root/assignments/$user.conf" || return 1
    info "Previous quota limits restored; account and data retained."
}
function lemper_hosting_status() {
    local root file user report
    root=$(lemper_hosting_root) || return 1
    [[ ! -L "$root/assignments" ]] || return 1
    printf 'ACCOUNT PLAN UID MOUNT PHASE USED_KIB USED_FILES SOFT_KIB HARD_KIB SOFT_FILES HARD_FILES\n'
    for file in "$root"/assignments/*.conf; do
        [[ -e "$file" || -L "$file" ]] || continue
        user=$(basename "$file" .conf)
        lemper_hosting_state_read "$user" || return 1
        local record=("${LEMPER_HOSTING_STATE[@]}") uid uuid
        uuid=$(lemper_quota_mount "${record[3]}") || return 1
        uid=$(lemper_hosting_user "$user" "${record[3]}") || return 1
        [[ "$uuid" == "${record[4]}" && "$uid" == "${record[2]}" ]] || return 1
        report=$(lemper_quota_read "$uid" "${record[3]}") || return 1
        printf '%s %s %s %s %s %s\n' "$user" "${record[1]}" "$uid" "${record[3]}" "${record[17]}" "$report"
    done
}
