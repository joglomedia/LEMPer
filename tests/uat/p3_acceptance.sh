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

# Only a disposable systemd container with an explicitly prepared ext4 /home.
set -euo pipefail
[[ -f /run/lemper-p3-uat-authorized && "$(id -u)" == 0 && -f /source/.env.dist ]] || {
    echo 'P3 UAT requires a designated disposable container and authorization marker.' >&2
    exit 1
}
[[ "$(findmnt -rn --mountpoint /home -o FSTYPE)" == ext4 ]] || exit 1
# Inspection: these modules define functions; activation copies only public code.
# shellcheck source=/dev/null
. /source/lib/core/loader.sh
lemper_load_module core/deployment
error() { echo "$*" >&2; }
info() { echo "$*"; }
export DRYRUN=false
lemper_cli_snapshot /source
install -d -m0700 /etc/lemper
sed -e 's/^SSH_PASSWORDLESS=.*/SSH_PASSWORDLESS=false/' \
    -e 's/^LOGGING=.*/LOGGING=false/' /source/.env.dist >/etc/lemper/lemper.conf
chmod 0600 /etc/lemper/lemper.conf
p3_checks=0
function check() {
    "$@"
    p3_checks=$((p3_checks + 1))
}
function rejects() {
    if "$@"; then
        echo 'Expected rejection.' >&2
        return 1
    fi
    p3_checks=$((p3_checks + 1))
}
check lemperctl hosting check
check lemperctl stack install quota
check lemperctl hosting plan put starter --disk-soft=256K --disk-hard=512K --files-soft=64 --files-hard=80
check lemperctl account p3tenant --plan=starter
check test "$(stat -c %a /etc/lemper/hosting/assignments/p3tenant.conf)" = 600
check test "$(stat -c %a /etc/lemper/accounts/p3tenant.conf)" = 600
check lemperctl hosting status
# A rejected plan must leave a new account locked and absent from web auth.
check lemperctl hosting plan put impossible --disk-soft=0 --disk-hard=1K --files-soft=0 --files-hard=2
rejects lemperctl account p3blocked --plan=impossible
check test "$(passwd -S p3blocked | awk '{print $2}')" = L
rejects grep -q '^p3blocked:' /srv/.htpasswd
check lemperctl hosting plan delete impossible --yes
# Real write under the tenant UID must hit kernel EDQUOT at the hard limit.
rejects runuser -u p3tenant -- dd if=/dev/zero of=/home/p3tenant/webapps/overflow bs=64K count=16 status=none
check rm -f /home/p3tenant/webapps/overflow
# The loop and variables execute in the tenant child shell.
# shellcheck disable=SC2016
rejects runuser -u p3tenant -- bash -c 'for ((i=0;i<100;i++)); do touch "/home/p3tenant/webapps/file-$i" || exit 1; done'
check find /home/p3tenant/webapps -type f -name 'file-*' -delete
rejects lemperctl hosting plan delete starter --yes
rejects lemperctl hosting plan put starter --disk-soft=256K --disk-hard=1M --files-soft=64 --files-hard=80
check lemperctl hosting plan put larger --disk-soft=1M --disk-hard=2M --files-soft=128 --files-hard=160
check lemperctl hosting assign p3tenant --plan=larger
check lemperctl hosting assign p3tenant --plan=larger
check runuser -u p3tenant -- dd if=/dev/zero of=/home/p3tenant/webapps/one-megabyte bs=64K count=16 status=none
rejects lemperctl hosting assign p3tenant --plan=starter
check lemperctl hosting detach p3tenant --yes --dry-run
check test -f /etc/lemper/hosting/assignments/p3tenant.conf
rejects lemperctl stack remove quota
check lemperctl hosting detach p3tenant --yes
check test -f /home/p3tenant/webapps/one-megabyte
check test ! -e /etc/lemper/hosting/assignments/p3tenant.conf
check lemperctl hosting plan delete starter --yes
# Repeat the plan path and confirm interruption recovery restores the baseline.
check lemperctl hosting assign p3tenant --plan=larger
check sed -i 's/ active$/ pending/' /etc/lemper/hosting/assignments/p3tenant.conf
check lemperctl hosting recover p3tenant --yes
check test ! -e /etc/lemper/hosting/assignments/p3tenant.conf
lemper_load_module services/hosting/quota
uid=$(id -u p3tenant)
quota_values=$(lemper_quota_read "$uid" /home)
read -r -a quota_values_array <<<"$quota_values"
check test "${quota_values_array[*]:2:4}" = '0 0 0 0'
check lemperctl hosting plan delete larger --yes
# Overlay rejection is exercised through the real CLI, preserving /etc/fstab.
check test ! -e /etc/lemper/hosting/plans/starter.conf
sed -i 's|^HOSTING_QUOTA_MOUNT=.*|HOSTING_QUOTA_MOUNT="/"|' /etc/lemper/lemper.conf
rejects lemperctl hosting check
sed -i 's|^HOSTING_QUOTA_MOUNT=.*|HOSTING_QUOTA_MOUNT="/home"|' /etc/lemper/lemper.conf
lemper_load_module core/progress
check bash -c 'source /source/lib/core/progress.sh; lemper_transfer_read /home/p3tenant/webapps/one-megabyte > /run/p3-transfer; cmp /run/p3-transfer /home/p3tenant/webapps/one-megabyte'
# Force a PTY to exercise actual optional pv progress, with binary stdout redirected.
check script -q -e -c 'bash -c "source /source/lib/core/progress.sh; lemper_transfer_read /home/p3tenant/webapps/one-megabyte > /run/p3-pv"' /run/p3-pv.log
check cmp /run/p3-pv /home/p3tenant/webapps/one-megabyte
printf 'P3 UAT passed: %s checks, including real disk/inode enforcement.\n' "$p3_checks"
