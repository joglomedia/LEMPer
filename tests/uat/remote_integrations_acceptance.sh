#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Remote Backup and Alert Acceptance                               |
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

set -euo pipefail
[[ $(id -u) == 0 && -f /run/.containerenv && -f /run/lemper-protocols-authorized &&
    $(cat /proc/1/comm) == systemd && $(findmnt -no OPTIONS /source) == ro,* ]] || exit 2
[[ "${1:-}" == '' || "${1:-}" == --restic-only ]] || exit 2
work=/run/lemper-protocols
logs=/var/log/lemper-integrations
repository="${LEMPER_UAT_RESTIC_REPOSITORY:-sftp:uatbackup@lemper-uat-backup:/srv/backup/repository}"
ssh_target="${LEMPER_UAT_SSH_TARGET:-uatbackup@lemper-uat-backup}"
[[ "$ssh_target" =~ ^[a-z][a-z0-9_-]*@[a-zA-Z0-9.-]+$ ]] || exit 2
install -d -m 0700 "$logs"
# shellcheck source=/dev/null
. /source/lib/core/loader.sh
lemper_load_module core/deployment
lemper_cli_snapshot /source >"$logs/activation.log" 2>&1
install -m 0600 /source/.env.dist /etc/lemper/lemper.conf
# shellcheck source=tests/uat/helpers.bash
. /source/tests/uat/helpers.bash
uat_profile_set /etc/lemper/lemper.conf RESTIC_REPOSITORY "\"$repository\""
uat_profile_set /etc/lemper/lemper.conf SSH_PASSWORDLESS false
uat_profile_set /etc/lemper/lemper.conf MONITOR_ALERT_EMAIL '"alerts@protocols.lemper-uat.test"'
uat_profile_set /etc/lemper/lemper.conf MONITOR_SMTP_HOST '"lemper-uat-backup"'
checks=0
function check() {
    local name="$1"
    shift
    if "$@" >"$logs/$name.log" 2>&1; then
        checks=$((checks + 1))
        printf 'PASS %s\n' "$name"
    else
        printf 'FAIL %s (private log: %s/%s.log)\n' "$name" "$logs" "$name"
        exit 1
    fi
}
check authenticated_endpoint ssh "$ssh_target" true
check repository_install lemperctl stack install restic --yes
install -d -m 0700 /srv/lemper-uat-data/app /srv/lemper-uat-data/mail
printf 'application-payload\n' >/srv/lemper-uat-data/app/probe
printf 'mail-payload\n' >/srv/lemper-uat-data/mail/message
check sftp_backup lemperctl data backup /srv/lemper-uat-data
check repository_integrity lemperctl data check
restore=$(mktemp -d "$work/remote-restore.XXXXXXXX")
check staged_restore lemperctl data restore latest --target "$restore"
check restored_application cmp /srv/lemper-uat-data/app/probe "$restore/srv/lemper-uat-data/app/probe"
check restored_mail cmp /srv/lemper-uat-data/mail/message "$restore/srv/lemper-uat-data/mail/message"
function password_mode() { [[ $(stat -c %a /etc/lemper/restic.pass) == 600 ]]; }
check protected_password password_mode
check scheduled_backup lemperctl data schedule /srv/lemper-uat-data
check scheduled_execution systemctl start lemper-data-backup.service
for counter in 1 2 3; do
    printf '%s\n' "$counter" >/srv/lemper-uat-data/app/counter
    lemperctl data backup /srv/lemper-uat-data >"$logs/backup-$counter.log" 2>&1
done
check remote_retention lemperctl data prune --keep=2
function snapshot_count() {
    RESTIC_REPOSITORY="$repository" RESTIC_PASSWORD_FILE=/etc/lemper/restic.pass \
        restic snapshots --json --tag lemper-data | jq -e 'length == 2'
}
check retained_snapshots snapshot_count
function unknown_host_refused() {
    local status=0
    : >"$work/untrusted-hosts"
    ssh -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$work/untrusted-hosts" \
        "$ssh_target" true >/dev/null 2>&1 || status=$?
    [[ "$status" == 255 ]]
}
check unknown_host_refused unknown_host_refused
if [[ "${1:-}" == --restic-only ]]; then
    printf 'Remote backup UAT: %s checks passed.\n' "$checks"
    exit 0
fi
check monitoring_install lemperctl stack install monit --yes
check monitoring_configuration lemperctl monitor check
config=/etc/lemper/monitoring/monitrc
cp -p "$config" "$work/monit.original"
printf 'fixture-only alert probe\n' >/srv/lemper-uat-alert-probe
sed -i 's/^set daemon 60$/set daemon 2/' "$config"
cat >>"$config" <<'MONIT'
check file lemper-uat-alert with path /srv/lemper-uat-alert-probe
    if does not exist then alert
MONIT
check monitoring_reload lemperctl monitor reload
rm /srv/lemper-uat-alert-probe
function alert_received() {
    local event="$1" _attempt
    for _attempt in {1..45}; do
        # Only two fixed fixture events may enter the remote shell program.
        case "$event" in
            failure)
                if ssh uatbackup@lemper-uat-backup 'for file in /srv/backup/smtp-capture/message.*; do if grep -Fq "lemper-uat-alert" "$file" && grep -Fiq "Does not exist" "$file"; then exit 0; fi; done; exit 1' 2>/dev/null; then return 0; fi
                ;;
            recovery)
                if ssh uatbackup@lemper-uat-backup 'for file in /srv/backup/smtp-capture/message.*; do if grep -Fq "lemper-uat-alert" "$file" && grep -Fiq "Exists" "$file"; then exit 0; fi; done; exit 1' 2>/dev/null; then return 0; fi
                ;;
            *) return 1 ;;
        esac
        sleep 2
    done
    return 1
}
check smtp_failure_alert alert_received failure
printf 'fixture-only alert probe\n' >/srv/lemper-uat-alert-probe
check smtp_recovery_alert alert_received recovery
install -m 0600 "$work/monit.original" "$config"
check monitoring_restored lemperctl monitor reload
rm /srv/lemper-uat-alert-probe
printf 'Remote integration UAT: %s checks passed.\n' "$checks"
