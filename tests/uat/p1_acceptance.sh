#!/usr/bin/env bash
# shellcheck disable=SC2016 # Child shell scripts intentionally retain literal expansions.
# Real P1 acceptance in a disposable systemd container with synthetic data only.
set -euo pipefail
[[ $(id -u) == 0 && -f /run/.containerenv && -f /run/lemper-p1-uat-authorized &&
   $(cat /proc/1/comm) == systemd ]] || { echo 'Designated disposable P1 UAT container required.' >&2; exit 2; }
[[ $(findmnt -no OPTIONS /source) == ro,* ]] || exit 2
logs=/var/log/lemper-p1-uat
install -d -m 0700 "$logs" /run/lemper-p1
install -d -m 0755 /checkout
cp -a /source/bin /source/lib /source/scripts /source/etc /source/share /checkout/
cp /source/.env.dist /checkout/.env.dist
# Only function definitions are sourced from legacy installers in this scoped UAT.
sed '/^echo "\[PHP & Extensions Installation\]/,$d' /checkout/scripts/install_php.sh > /run/lemper-p1/php-functions.sh
sed '/^echo "\[MariaDB (MySQL drop-in replacement) Installation\]/,$d' /checkout/scripts/install_mariadb.sh > /run/lemper-p1/mariadb-functions.sh
# shellcheck source=/dev/null
. /checkout/lib/core/loader.sh
# shellcheck source=/dev/null
. /run/lemper-p1/php-functions.sh
# shellcheck source=/dev/null
. /run/lemper-p1/mariadb-functions.sh
# shellcheck source=/dev/null
. /etc/os-release
export DISTRIB_NAME="$ID" RELEASE_NAME="$VERSION_CODENAME" MYSQL_VERSION=11.4 PHP_EXTENSIONS=""
export DRYRUN=false
count=0
check() {
    local name="$1"
    shift
    if "$@" > "$logs/$name.log" 2>&1; then
        count=$((count+1)); printf 'PASS %02d %s\n' "$count" "$name"
    else printf 'FAIL %s (private log: %s/%s.log)\n' "$name" "$logs" "$name"; exit 1; fi
}
check php-scoped-repository add_php_repo
check mariadb-scoped-repository add_mariadb_repo
repo_repeat() {
    cp /usr/share/keyrings/debsuryorg-archive-keyring.gpg "/etc/apt/trusted.gpg.d/ondrej-php-$RELEASE_NAME.gpg"
    cp /etc/apt/keyrings/mariadb.gpg /etc/apt/trusted.gpg.d/mariadb-keyring-2019.gpg
    local before
    before=$(find /etc/apt/sources.list.d -type f \( -name '*.list' -o -name '*.sources' \) -exec sha256sum {} + | sort)
    add_php_repo && add_mariadb_repo || return 1
    [[ ! -e "/etc/apt/trusted.gpg.d/ondrej-php-$RELEASE_NAME.gpg" && ! -e /etc/apt/trusted.gpg.d/mariadb-keyring-2019.gpg ]] || return 1
    [[ "$before" == "$(find /etc/apt/sources.list.d -type f \( -name '*.list' -o -name '*.sources' \) -exec sha256sum {} + | sort)" ]]
}
check repository-repeat-and-legacy-key-retirement repo_repeat
check install-real-packages apt-get install -y -qq cron mariadb-server php8.4-cli
check real-services systemctl restart mariadb cron
check cli-activation lemper_load_module core/deployment
check cli-snapshot lemper_cli_snapshot /checkout
install -m 0600 /checkout/.env.dist /etc/lemper/lemper.conf
# Root socket auth is confined to this disposable server; there are no live credentials.
mariadb -e "CREATE DATABASE IF NOT EXISTS p1db; DROP TABLE IF EXISTS p1db.probe; CREATE TABLE p1db.probe(id INT PRIMARY KEY, value VARCHAR(64)); INSERT INTO p1db.probe VALUES(42,'restored-data');"
check real-gzip-backup lemperctl db backup --dbname=p1db --dbfile=/var/backups/lemper/p1
backup=$(find /var/backups/lemper/p1 -name 'p1db_*.sql.gz' | head -1)
check dump-mode test "$(stat -c %a "$backup")" = 600
mariadb -e 'DELETE FROM p1db.probe;'
check real-gzip-restore lemperctl db restore --dbname=p1db --dbfile="$backup"
check restored-data bash -c '[[ $(mariadb -N -B -e "SELECT value FROM p1db.probe WHERE id=42") == restored-data ]]'
check real-plain-export lemper-cli db export --dbname=p1db --dbfile=/var/backups/lemper/p1/plain.sql
mariadb -e 'DELETE FROM p1db.probe;'
check real-plain-import lemperctl db import --dbname=p1db --dbfile=/var/backups/lemper/p1/plain.sql
check imported-data bash -c '[[ $(mariadb -N -B -e "SELECT COUNT(*) FROM p1db.probe") == 1 ]]'
check scheduled-backup lemperctl db backup-schedule --dbname=p1db --dbschedule='*/15 2-4 * * 1,5' --dbfile=/var/backups/lemper/p1
check repeated-schedule lemperctl db backup-schedule --dbname=p1db --dbschedule='0 3 * * *' --dbfile=/var/backups/lemper/p1
check cron-preservation bash -c '[[ $(crontab -l | grep -c -- --dbname=p1db) == 1 ]]'
# Password punctuation must remain literal SQL data and stay out of output/arguments.
printf '%s\n' "synthetic'\\;password" > /run/lemper-p1/password
chmod 0600 /run/lemper-p1/password
mariadb -e "DROP USER IF EXISTS 'p1app'@'localhost';"
check quoted-password-account lemperctl db account create --dbuser=p1app --dbpass-file=/run/lemper-p1/password
check quoted-password-login bash -c 'IFS= read -r MYSQL_PWD < /run/lemper-p1/password; export MYSQL_PWD; mariadb -u p1app -N -B -e "SELECT 1"'
check quoted-password-change lemperctl db account passwd --dbuser=p1app --dbpass-file=/run/lemper-p1/password
check password-login-after-change bash -c 'IFS= read -r MYSQL_PWD < /run/lemper-p1/password; export MYSQL_PWD; mariadb -u p1app -N -B -e "SELECT 1"'
check account-grant lemperctl db account access --dbuser=p1app --dbname=p1db
check account-schedule lemperctl db backup-schedule --dbname=p1db --dbuser=p1app --dbpass-file=/run/lemper-p1/password
check protected-cron-password test "$(stat -c %a /etc/lemper/backup-credentials/p1db-p1app.pass)" = 600
check cron-command-backup bash -c 'command=$(crontab -l | awk "/lemperctl db backup/ {for(i=6;i<=NF;i++) printf \"%s%s\", \$i, i==NF?\"\\n\":\" \"}"); bash -c "$command"'
dry_run() {
    local before after
    before=$(find /var/backups/lemper/p1 -type f -exec sha256sum {} + | sort)
    lemperctl db export --dbname=p1db --dbfile=/var/backups/lemper/p1/plain.sql --dry-run || return 1
    lemperctl db backup --dbname=p1db --dbfile=/var/backups/lemper/p1/new --dry-run || return 1
    after=$(find /var/backups/lemper/p1 -type f -exec sha256sum {} + | sort)
    [[ "$before" == "$after" && ! -e /var/backups/lemper/p1/new ]]
}
check db-dry-run dry_run
reject_invalid() {
    if lemperctl db backup '--dbname=p1db;touch /run/lemper-p1/injected'; then return 1; fi
    if lemperctl db backup-schedule --dbname=p1db '--dbschedule=0 2 * * *%touch /run/lemper-p1/injected'; then return 1; fi
    if lemperctl db export --dbname=p1db --extra-args=MYSQLCLI=/bin/false; then return 1; fi
    [[ ! -e /run/lemper-p1/injected ]]
}
check db-invalid-input reject_invalid
install -d -m 0700 /etc/lemper/vhost.d
install -d -m 0755 /etc/nginx/sites-available
cat > /etc/lemper/vhost.d/p1.test.conf <<'INI'
[p1.test]
APP_FRAMEWORK="laravel"
APP_DB_PASS="synthetic-diagnostic-password"
APP_ADMIN_PASS="synthetic-admin-password"
APP_WEBROOT="/home/app/quoted%path"
INI
chmod 0600 /etc/lemper/vhost.d/p1.test.conf
printf 'server_name p1.test;\n' > /etc/nginx/sites-available/p1.test.conf
check site-text-redaction bash -c 'output=$(lemperctl site show p1.test --app); [[ "$output" == *"[REDACTED]"* && "$output" != *synthetic-diagnostic-password* && "$output" != *synthetic-admin-password* ]]'
check site-json-redaction bash -c 'lemperctl site show p1.test --json | jq -e '\''.domain=="p1.test" and .app_metadata["p1.test"].app_db_pass=="[REDACTED]"'\'''
check installed-php php8.4 -r 'exit(PHP_MAJOR_VERSION == 8 && PHP_MINOR_VERSION == 4 ? 0 : 1);'
printf '%s checks passed on %s %s (%s).\n' "$count" "$DISTRIB_NAME" "$RELEASE_NAME" "$(dpkg --print-architecture)"
