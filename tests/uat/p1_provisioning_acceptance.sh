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

# Native MariaDB checks only in a designated fresh disposable Linux container.
set -euo pipefail
[[ "$EUID" == 0 && -f /run/lemper-p1-provisioning-authorized && -f /source/.env.dist ]] || {
    echo 'Requires an authorized disposable MariaDB UAT container.' >&2
    exit 1
}
suffix="${1:-}"
[[ "$suffix" =~ ^[a-z0-9]{0,8}$ ]] || exit 1
work="/var/tmp/lemper-p1-provisioning$suffix"
[[ ! -e "$work" ]] || {
    echo 'Use a fresh UAT container.' >&2
    exit 1
}
install -d -m0700 "$work" "$work/mysql"
# shellcheck source=/dev/null
. /source/lib/core/loader.sh
error() { printf '%s\n' "$*" >&2; }
success() { printf '%s\n' "$*"; }
export DRYRUN=false LEMPER_OPERATION_LOCK="$work/operation.lock"
export LEMPER_MYSQL_MAIN_CONFIG="$work/my.cnf"
export LEMPER_MYSQL_CONFIG_DIR="$work/mysql" LEMPER_MARIADB_PROFILE="$work/profile"
export MARIABACKUP_USER="uatbackup$suffix" MARIABACKUP_PASS="'quoted \" slash\\ dollar\$(literal) end'"
export MARIABACKUP_USERNAME='' MARIABACKUP_PASSWORD='' MYSQL_ROOT_PASSWORD=''
cp /source/.env.dist "$work/profile"
chmod 0600 "$work/profile"
lemper_load_module services/mariadb/backup
checks=0
check() {
    local label="$1"
    shift
    if ! "$@" >"$work/$label.log" 2>&1; then
        printf 'FAIL %s\n' "$label" >&2
        return 1
    fi
    checks=$((checks + 1))
    printf 'ok %s\n' "$label"
}
reject() { if "$@" >/dev/null 2>&1; then return 1; fi; }
login() { MYSQL_PWD="$MARIABACKUP_PASS" mariadb --user="$MARIABACKUP_USER" -e 'SELECT 1;' >/dev/null; }
option_roundtrip() {
    local defaults
    defaults=$(my_print_defaults --defaults-file="$work/mysql/50-mariabackup.cnf" mariabackup)
    [[ "$defaults" == *"--password=$MARIABACKUP_PASS"* ]]
}
check provision lemper_with_lock lemper_mariabackup_provision
check private-dropin test "$(stat -c %a "$work/mysql/50-mariabackup.cnf")" = 600
check private-profile test "$(stat -c %a "$work/profile")" = 600
check actual-login login
check option-reader option_roundtrip
# Compare hashes through mysql.user on both distributions; do not print them.
before=$(mariadb -N -B -e "SELECT Password FROM mysql.user WHERE User='$MARIABACKUP_USER';")
rm "$work/mysql/50-mariabackup.cnf"
check repair-existing lemper_with_lock lemper_mariabackup_provision
check existing-password-preserved test "$(mariadb -N -B -e "SELECT Password FROM mysql.user WHERE User='$MARIABACKUP_USER';")" = "$before"
check repeated-provision lemper_with_lock lemper_mariabackup_provision
check repeated-login login
original_password="$MARIABACKUP_PASS"
MARIABACKUP_PASS=wrong
check wrong-credentials reject lemper_with_lock lemper_mariabackup_provision
MARIABACKUP_PASS="$original_password"
check original-login login
MARIABACKUP_PASS=
check recover-dropin lemper_with_lock lemper_mariabackup_provision
MARIABACKUP_PASS="$original_password"
check recovered-login login
datadir=$(mariadb -N -B -e 'SELECT @@datadir;')
[[ "$datadir" == /* && "$datadir" != / ]] || exit 1
check physical-backup mariadb-backup --defaults-file="$work/mysql/50-mariabackup.cnf" \
    --backup --datadir="$datadir" --target-dir="$work/physical"
check physical-prepare mariadb-backup --defaults-file="$work/mysql/50-mariabackup.cnf" \
    --prepare --target-dir="$work/physical"
printf '[mysqld]\nport=3306\n' >"$work/my.cnf"
cat "$work/mysql/50-mariabackup.cnf" >>"$work/my.cnf"
chmod 0644 "$work/my.cnf"
rm "$work/mysql/50-mariabackup.cnf"
MARIABACKUP_PASS=""
check migrate-inline lemper_with_lock lemper_mariabackup_provision
check inline-retired reject grep -qE '^[[:space:]]*(\[mariabackup\]|password[[:space:]]*=)' "$work/my.cnf"
MARIABACKUP_PASS="$original_password"
check migrated-login login
# Exercise the standalone installer reconciliation path on an existing server.
check installer-repair env LEMPER_ENV_FILE="$work/profile" \
    bash /source/scripts/install_mariadb.sh
check installer-password-preserved login
export MARIABACKUP_USER="legacyuat$suffix" MARIABACKUP_USERNAME="legacyuat$suffix" MARIABACKUP_PASS='' MARIABACKUP_PASSWORD=synthetic-legacy
export LEMPER_MYSQL_CONFIG_DIR="$work/legacy-mysql" LEMPER_MYSQL_MAIN_CONFIG="$work/legacy-main.cnf"
check legacy-key-provision lemper_with_lock lemper_mariabackup_provision
MARIABACKUP_PASS=synthetic-legacy
check legacy-login login
printf 'P1 provisioning UAT passed: %s checks\n' "$checks"
