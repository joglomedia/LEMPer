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

# Administrators enable quotas before LEMPer takes over individual UID limits.
# Never remount a filesystem or change fstab/kernel packages from this driver.
function lemper_quota_mount() {
    local mount="${1}" canonical target filesystem uuid state
    [[ "$mount" =~ ^/[a-zA-Z0-9_./-]*$ && "$mount" != *..* ]] || {
        error "Invalid quota mount."
        return 1
    }
    canonical=$(realpath -e -- "$mount") || return 1
    [[ "$canonical" == "$mount" ]] || {
        error "Use the canonical quota mount path."
        return 1
    }
    read -r target filesystem uuid < <(findmnt -rn --mountpoint "$mount" -o TARGET,FSTYPE,UUID)
    [[ "$target" == "$mount" && "$filesystem" == ext4 && "$uuid" =~ ^[a-fA-F0-9-]{36}$ ]] || {
        error "Hosting quotas require a quota-ready ext4 mount; overlay/OpenVZ and unsupported filesystems cannot enforce these limits."
        return 1
    }
    if ! command -v setquota >/dev/null || ! command -v repquota >/dev/null || ! command -v quotaon >/dev/null; then
        error "Install quota tools first: lemperctl stack install quota."
        return 1
    fi
    # quotaon -p returns the number of enabled quotas, so status 1 is normal.
    state=$(LC_ALL=C quotaon -p -u "$mount" 2>/dev/null) || true
    [[ "$state" == *' is on' ]] || {
        error "User quotas are inactive. Enable them using your distribution/filesystem maintenance procedure first."
        return 1
    }
    printf '%s\n' "$uuid"
}

# Numeric CSV avoids wrapping, locale-dependent units and username ambiguity.
# Return used blocks, used inodes, then the four existing quota limits.
function lemper_quota_read() {
    local uid="$1" mount="$2" report row
    report=$(LC_ALL=C repquota -uvnp -O csv "$mount") || return 1
    [[ "${report%%$'\n'*}" == 'User,BlockStatus,FileStatus,BlockUsed,BlockSoftLimit,BlockHardLimit,BlockGrace,FileUsed,FileSoftLimit,FileHardLimit,FileGrace' ]] || {
        error "Unsupported quota report format."
        return 1
    }
    row=$(awk -F, -v uid="#$uid" '$1 == uid {print $4, $8, $5, $6, $9, $10}' <<<"$report")
    [[ -n "$row" ]] || row='0 0 0 0 0 0'
    [[ "$row" =~ ^[0-9]+\ [0-9]+\ [0-9]+\ [0-9]+\ [0-9]+\ [0-9]+$ ]] || return 1
    printf '%s\n' "$row"
}

function lemper_quota_set() {
    local uid="$1" mount="$2"
    shift 2
    lemper_exec setquota -u "$uid" "$@" "$mount" || return 1
    [[ "${DRYRUN:-false}" != true ]] || return 0
    local report values=()
    report=$(lemper_quota_read "$uid" "$mount") || return 1
    read -r -a values <<<"$report"
    [[ "${values[*]:2:4}" == "$*" ]] || {
        error "Quota verification failed."
        return 1
    }
}
