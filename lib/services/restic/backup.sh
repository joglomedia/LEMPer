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



function lemper_restic_environment() {
    local repository="${RESTIC_REPOSITORY:-/var/backups/lemper/data}" password_file="${RESTIC_PASSWORD_FILE:-/etc/lemper/restic.pass}"
    [[ "$repository" != *$'\n'* && "$repository" != *$'\r'* ]] || {
        error "Repository must not contain embedded credentials or control characters."; return 1;
    }
    [[ "$password_file" == /* && "$password_file" != *$'\n'* && "$password_file" != *$'\r'* ]] || {
        error "Restic password file must be an absolute protected path."; return 1;
    }
    lemper_load_module services/mariadb/database || return 1
    lemper_db_directory_safe "${password_file%/*}" || { error "Untrusted Restic password-file directory."; return 1; }
    # Local repositories are protected from writable ancestors; remote backends stay data.
    if [[ "$repository" == /* ]]; then
        lemper_load_module services/mariadb/database || return 1
        lemper_db_directory_safe "$repository" || { error "Unsafe backup repository directory."; return 1; }
    elif [[ "$repository" == sftp:* ]]; then
        [[ "$repository" =~ ^sftp:([A-Za-z_][A-Za-z0-9_.-]*@)?[A-Za-z0-9][A-Za-z0-9.-]*:/[A-Za-z0-9_./-]+$ ]] || {
            error "SFTP repositories require a safe user/hostname and absolute path; configure SSH keys separately."; return 1;
        }
    elif [[ "$repository" =~ ^(s3:|b2:|azure:|gs:|rest:https://) ]]; then
        [[ "$repository" != *'@'* && "$repository" != *[[:space:]]* ]] || {
            error "Remote repositories cannot embed credentials or whitespace."; return 1;
        }
    else
        error "Specify an absolute local repository or a supported Restic remote backend."; return 1
    fi
    if [[ "${DRYRUN:-false}" != true ]]; then
        [[ -f "$password_file" && ! -L "$password_file" ]] || { error "Restic password file is missing."; return 1; }
        local owner mode
        read -r owner mode < <(stat -c '%u %a' "$password_file") || return 1
        [[ "$owner" == "$EUID" && "$mode" == 600 ]] || { error "Restic password file must be owned by root with mode 0600."; return 1; }
    fi
    export RESTIC_REPOSITORY="$repository" RESTIC_PASSWORD_FILE="$password_file"
}

function lemper_restic_run() (
    lemper_restic_environment || return 1
    # Credentials are inherited through a protected environment/file, never rendered as argv.
    lemper_exec restic "$@"
)

function lemper_restic_init() {
    lemper_restic_environment || return 1
    if [[ "${DRYRUN:-false}" == true ]]; then info "Would initialize encrypted data repository."; return 0; fi
    if lemper_restic_run snapshots --json >/dev/null 2>&1; then info "Repository already initialized."; return 0; fi
    if [[ "$RESTIC_REPOSITORY" == /* && -e "$RESTIC_REPOSITORY/config" ]]; then
        error "Existing repository cannot be opened; check credentials rather than reinitializing it."; return 1
    fi
    lemper_restic_run init
}

function lemper_restic_paths_valid() {
    local paths=("$@") path
    [[ ${#paths[@]} -gt 0 ]] || { error "Specify absolute application/mail paths to back up."; return 1; }
    for path in "${paths[@]}"; do
        [[ "$path" == /* && -d "$path" && ! -L "$path" && "$path" != *$'\n'* ]] || { error "Invalid data backup path."; return 1; }
        case "$path" in /|/proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/run|/run/*) error "Refusing system pseudo-filesystem backup."; return 1 ;; esac
        if [[ "${RESTIC_REPOSITORY:-/var/backups/lemper/data}" == "$path" || "${RESTIC_REPOSITORY:-/var/backups/lemper/data}" == "$path"/* ]]; then
            error "Backup source contains its own repository."; return 1
        fi
    done
    return 0
}
function lemper_restic_backup() {
    lemper_restic_paths_valid "$@" || return 1
    lemper_restic_run backup --tag lemper-data --exclude "${RESTIC_PASSWORD_FILE:-/etc/lemper/restic.pass}" -- "$@"
}

function lemper_restic_restore() {
    local snapshot="$1" target="$2"
    [[ "$snapshot" =~ ^[a-f0-9]{8,64}$ || "$snapshot" == latest ]] || { error "Invalid snapshot ID."; return 1; }
    lemper_load_module services/mariadb/database || return 1
    lemper_db_directory_safe "$target" || { error "Restore target must be a root-owned protected path."; return 1; }
    case "$target" in /|/etc|/etc/*|/usr|/usr/*|/var|/home|/srv|/opt|/root) error "Use a separate staging directory for restoration."; return 1 ;; esac
    if [[ -e "$target" ]] && [[ -n "$(find "$target" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        error "Restore target must be empty; restore into staging before replacing live files."; return 1
    fi
    lemper_exec install -d -m 0700 -- "$target" || return 1
    lemper_restic_run restore "$snapshot" --tag lemper-data --target "$target"
}

function lemper_restic_prune() {
    local keep="$1"
    [[ "$keep" =~ ^[0-9]{1,4}$ ]] || { error "Invalid retention count."; return 1; }
    ((10#$keep > 0)) || { error "Retention requires a positive --keep count."; return 1; }
    # Group by host/path/tag so one site's backup cannot evict another site's history.
    lemper_restic_run forget --tag lemper-data --group-by host,paths,tags --keep-last "$keep" --prune
}

function lemper_restic_schedule() {
    local paths=("$@") path root=/etc/lemper/data-backup
    lemper_restic_paths_valid "${paths[@]}" || return 1
    for path in "${paths[@]}"; do
        [[ "$path" =~ ^/[A-Za-z0-9_./-]+$ && -d "$path" && ! -L "$path" ]] || { error "Scheduled paths must be absolute directories without shell characters."; return 1; }
    done
    lemper_restic_environment || return 1
    if [[ "${DRYRUN:-false}" == true ]]; then info "Would schedule encrypted data backups."; return 0; fi
    install -d -m 0700 "$root" || return 1
    if [[ ! -f "$root/managed" ]] && { [[ -e /etc/systemd/system/lemper-data-backup.service ]] || [[ -e /etc/systemd/system/lemper-data-backup.timer ]]; }; then
        error "Refusing to replace unmanaged data-backup units."; return 1
    fi
    [[ ! -e "$root/paths" ]] || cp -p "$root/paths" "$root/paths.previous" || return 1
    printf '%s\n' "${paths[@]}" > "$root/paths" || return 1
    chmod 0600 "$root/paths" || return 1
    local config="${CONFIG_FILE:-/etc/lemper/lemper.conf}"
    [[ "$config" == /etc/lemper/lemper.conf ]] || { error "Persist backup settings in the installed configuration before scheduling."; return 1; }
    # A fixed runner reads root-only data; no shell programs are built from user paths.
    cat > /etc/systemd/system/lemper-data-backup.service <<'UNIT'
[Unit]
Description=LEMPer encrypted application data backup
[Service]
Type=oneshot
UMask=0077
ExecStart=/usr/local/bin/lemperctl data run-scheduled
UNIT
    cat > /etc/systemd/system/lemper-data-backup.timer <<'UNIT'
[Unit]
Description=Daily LEMPer encrypted application data backup
[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=15m
[Install]
WantedBy=timers.target
UNIT
    systemd-analyze verify /etc/systemd/system/lemper-data-backup.service /etc/systemd/system/lemper-data-backup.timer || return 1
    touch "$root/managed" || return 1
    lemper_exec systemctl daemon-reload || return 1
    lemper_exec systemctl enable --now lemper-data-backup.timer || return 1
    touch "$root/managed"
}
