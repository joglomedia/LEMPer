#!/usr/bin/env bash
# System-changing mail UAT: only a designated disposable Podman/systemd container.
set -euo pipefail
[[ $(id -u) == 0 && -f /run/.containerenv && -f /run/lemper-mail-uat-authorized &&
$(cat /proc/1/comm) == systemd ]] || {
    echo 'Designated mail UAT container required.' >&2
    exit 2
}
[[ $(findmnt -no OPTIONS /source) == ro,* ]] || exit 2
logs=/var/log/lemper-mail-uat
install -d -m 0700 "$logs" /checkout /run/mail-uat
cp -a /source/bin /source/lib /source/scripts /source/etc /source/share /checkout/
cp /source/.env.dist /checkout/.env
chmod 0600 /checkout/.env
cp /source/tests/uat/helpers.bash /source/tests/uat/mail_helpers.bash /run/mail-uat/
# shellcheck source=tests/uat/helpers.bash
. /run/mail-uat/helpers.bash
# shellcheck source=tests/uat/mail_helpers.bash
. /run/mail-uat/mail_helpers.bash
while IFS='|' read -r key value; do uat_profile_set /checkout/.env "$key" "$value"; done <<'PROFILE'
AUTO_INSTALL|true
INSTALL_MAILER|true
INSTALL_SPFDKIM|true
FORCE_INSTALL|false
ENVIRONMENT|"development"
SERVER_HOSTNAME|"mail.lemper-uat.test"
SERVER_IP|"127.0.0.1"
SENDER_DOMAIN|"first-uat.test"
MAILER_HOSTNAME|"mail.lemper-uat.test"
MAILER_CERT_PATH|"/run/mail-uat/tls"
SSH_PASSWORDLESS|false
PROFILE
install -d -m 0700 /run/mail-uat/tls
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=Mail-UAT-CA \
    -keyout /run/mail-uat/ca.key -out /run/mail-uat/ca.pem >"$logs/certificates.log" 2>&1
openssl req -new -newkey rsa:2048 -nodes -subj /CN=mail.lemper-uat.test \
    -keyout /run/mail-uat/tls/privkey.pem -out /run/mail-uat/mail.csr >>"$logs/certificates.log" 2>&1
printf 'subjectAltName=DNS:mail.lemper-uat.test\nextendedKeyUsage=serverAuth\n' >/run/mail-uat/extensions
openssl x509 -req -in /run/mail-uat/mail.csr -CA /run/mail-uat/ca.pem -CAkey /run/mail-uat/ca.key \
    -CAcreateserial -days 2 -extfile /run/mail-uat/extensions -out /run/mail-uat/tls/fullchain.pem >>"$logs/certificates.log" 2>&1
chmod 0600 /run/mail-uat/tls/privkey.pem
printf '\n127.0.0.1 mail.lemper-uat.test\n' >>/etc/hosts
for name in password replacement; do
    (
        umask 077
        openssl rand -hex 30 >"/run/mail-uat/$name"
    )
done
trap mail_close EXIT
cases=0
function uat_case() {
    local name="$1"
    shift
    cases=$((cases + 1))
    if "$@" >"$logs/$name.log" 2>&1; then
        printf 'PASS %s\n' "$name"
    else
        printf 'FAIL %s (log: %s)\n' "$name" "$logs/$name.log"
        if [[ "$name" == installation ]]; then
            uat_apt_failure_summary "$logs/$name.log"
            awk -F: '/\/lib\/services\/mail\// && $NF ~ /^[1-9][0-9]*$/ {print}' "$logs/install-locations" | tail -12
            awk -F: '$3 ~ /^lemper_mail_(author_prepare|template|postfix_configure|check|reload)$/ {last[$3]=$0}
                END {for (stage in last) print last[stage]}' "$logs/install-locations"
            # This is the first case, before any SMTP traffic or account setup.
            # Only the dedicated worker's startup journal survives unit rollback.
            journalctl -b -u lemper-mail-author.service --no-pager -o cat -n 35
        fi
        exit 1
    fi
}
function install_mail() {
    BASH_ENV=/source/tests/uat/bootstrap_trace.bash LEMPER_UAT_BOOTSTRAP_TRACE=true \
        bash /checkout/scripts/install_mailer.sh 19>"$logs/install-locations"
}
function activate_cli() {
    bash -c '
        . /checkout/lib/core/loader.sh
        . /checkout/lib/core/deployment.sh
        lemper_cli_snapshot /checkout
    '
    install -m 0600 /checkout/.env /etc/lemper/lemper.conf
}
function services() {
    systemctl is-active --quiet postfix dovecot opendkim lemper-mail-author || return 1
    test -S /var/spool/postfix/private/auth || return 1
    test -S /var/spool/postfix/private/dovecot-lmtp || return 1
    [[ $(stat -c '%U:%G:%a' /var/cache/lemper-mail-author) == lemper-mail-author:postfix:700 ]] || return 1
    lemperctl mail check
}
function submission_author() {
    local subject
    subject="Authenticated alias author $(date +%s%N)"
    smtp_secure && smtp_login bob@second-uat.test /run/mail-uat/password || return 1
    smtp_send bob@second-uat.test alice@first-uat.test "$subject" \
        $'"Operations, Team"\r\n\t<team@second-uat.test>' || return 1
    if smtp_send bob@second-uat.test alice@first-uat.test 'Unassigned author' alice@first-uat.test; then return 1; fi
    [[ "$smtp_code" == 550 || "$smtp_code" == 554 ]] || return 1
    if smtp_send bob@second-uat.test alice@first-uat.test 'Multiple author fields' \
        $'bob@second-uat.test\r\nfRoM: bob@second-uat.test'; then return 1; fi
    [[ "$smtp_code" == 550 || "$smtp_code" == 554 ]] || return 1
    mail_close
    mail_wait_message alice@first-uat.test "$subject" second-uat.test || return 1
    systemctl stop lemper-mail-author || return 1
    mail_plain 127.0.0.1 587 && smtp_reply || return 1
    if [[ "$smtp_code" == 220 ]]; then
        smtp_command 'EHLO mail-uat.test' || return 1
        if [[ "$smtp_code" == 250 ]]; then smtp_command STARTTLS || return 1; fi
    fi
    [[ "$smtp_code" == 4* ]] || return 1
    mail_close
    smtp_open 127.0.0.1 25 || return 1
    mail_close
    systemctl start lemper-mail-author
}
function repeat_install() {
    local before after
    before=$(sha256sum /etc/lemper-mail/keys/first-uat.test/lemper.private /etc/lemper-mail/current/accounts)
    install_mail
    after=$(sha256sum /etc/lemper-mail/keys/first-uat.test/lemper.private /etc/lemper-mail/current/accounts)
    [[ "$before" == "$after" ]]
}
function delivery() {
    local id remote_ip primary secondary incoming
    id=$(date +%s%N)
    primary="LEMPer mail UAT $id" secondary="Second domain UAT $id" incoming="Incoming UAT $id"
    remote_ip=$(hostname -I)
    remote_ip="${remote_ip%% *}"
    smtp_open "$remote_ip" 25 || return 1
    [[ "${smtp_response^^}" != *AUTH* ]] || return 1
    smtp_command 'MAIL FROM:<probe@first-uat.test>' && [[ "$smtp_code" == 250 ]] || return 1
    smtp_command 'RCPT TO:<nobody@first-uat.test>' && ((smtp_code >= 500)) || return 1
    smtp_command 'RCPT TO:<outsider@example.net>' && ((smtp_code >= 500)) || return 1
    smtp_open mail.lemper-uat.test 587 || return 1
    [[ "${smtp_response^^}" != *AUTH* ]] || return 1
    smtp_command 'MAIL FROM:<alice@first-uat.test>' && ((smtp_code >= 500)) || return 1
    smtp_secure && smtp_login alice@first-uat.test /run/mail-uat/password || return 1
    smtp_command 'MAIL FROM:<bob@second-uat.test>' && [[ "$smtp_code" == 250 ]] || return 1
    smtp_command 'RCPT TO:<alice@first-uat.test>' && ((smtp_code >= 500)) || return 1
    smtp_command RSET && [[ "$smtp_code" == 250 ]] || return 1
    smtp_send alice@first-uat.test team@second-uat.test "$primary" || return 1
    mail_close
    mail_wait_message bob@second-uat.test "$primary" first-uat.test || return 1
    smtp_secure && smtp_login bob@second-uat.test /run/mail-uat/password || return 1
    smtp_send bob@second-uat.test alice@first-uat.test "$secondary" || return 1
    smtp_open "$remote_ip" 25 && smtp_send remote@outside-uat.test team@second-uat.test "$incoming" || return 1
    mail_close
    mail_wait_message alice@first-uat.test "$secondary" second-uat.test || return 1
    mail_wait_message bob@second-uat.test "$incoming" || return 1
    mail_tls 25 "" smtp && smtp_command 'EHLO mail-uat.test' && [[ "$smtp_code" == 250 ]] || return 1
    mail_close
    imap_open 143 && imap_login bob@second-uat.test /run/mail-uat/password || return 1
    mail_close
}
function literal_address() {
    lemperctl mail account add tag+literal@first-uat.test --password-file /run/mail-uat/password
    local subject
    subject="Literal plus $(date +%s%N)"
    smtp_secure && smtp_login tag+literal@first-uat.test /run/mail-uat/password || return 1
    smtp_send tag+literal@first-uat.test tag+literal@first-uat.test "$subject" || return 1
    mail_close
    mail_wait_message tag+literal@first-uat.test "$subject" || return 1
    [[ -d /var/vmail/first-uat.test/tag+literal/Maildir && ! -e /var/vmail/first-uat.test/tag/Maildir ]] || return 1
    lemperctl mail account delete tag+literal@first-uat.test --purge --yes
}
function password_and_disable() {
    lemperctl mail account edit alice@first-uat.test --password-file /run/mail-uat/replacement
    imap_open || return 1
    if imap_login alice@first-uat.test /run/mail-uat/password; then
        mail_close
        return 1
    fi
    imap_login alice@first-uat.test /run/mail-uat/replacement || return 1
    mail_close
    imap_open && imap_login alice@first-uat.test /run/mail-uat/replacement || return 1
    lemperctl mail account edit alice@first-uat.test --disable || return 1
    if imap_command NOOP; then
        mail_close
        return 1
    fi
    mail_close
    imap_open || return 1
    if imap_login alice@first-uat.test /run/mail-uat/replacement; then
        mail_close
        return 1
    fi
    mail_close
    lemperctl mail account edit alice@first-uat.test --enable
}
function dry_run() {
    local before
    before=$(readlink /etc/lemper-mail/current)
    lemperctl mail account delete bob@second-uat.test --dry-run --yes
    [[ "$before" == "$(readlink /etc/lemper-mail/current)" ]]
}
function delete_accounts() {
    if lemperctl mail account delete bob@second-uat.test --yes; then return 1; fi
    lemperctl mail alias edit team@second-uat.test alice@first-uat.test
    lemperctl mail account delete bob@second-uat.test --yes
    test -d /var/vmail/second-uat.test/bob/Maildir
    lemperctl mail alias delete team@second-uat.test --yes
    lemperctl mail domain delete second-uat.test --yes
    lemperctl mail account delete alice@first-uat.test --purge --yes
    test ! -d /var/vmail/first-uat.test/alice
}
function remove_mail() {
    AUTO_REMOVE=true bash /checkout/scripts/remove_mailer.sh
    if dpkg-query -W -f='${Status}' postfix 2>/dev/null | grep -q 'install ok installed'; then return 1; fi
    test -d /var/vmail/second-uat.test/bob/Maildir
    test -s /etc/lemper-mail/keys/first-uat.test/lemper.private
}
uat_case installation install_mail
uat_case cli_activation activate_cli
uat_case configuration_and_sockets services
uat_case stack_reload lemperctl stack reload mailer
uat_case stack_package_update lemperctl stack update mailer
uat_case add_domain lemperctl mail domain add second-uat.test
uat_case add_first_account lemperctl mail account add alice@first-uat.test --password-file /run/mail-uat/password
uat_case add_second_account lemperctl mail account add bob@second-uat.test --password-file /run/mail-uat/password
uat_case cross_domain_alias lemperctl mail alias add team@second-uat.test bob@second-uat.test
uat_case smtp_tls_auth_delivery_imap_dkim delivery
uat_case authenticated_submission_author submission_author
uat_case literal_plus_address literal_address
uat_case repeated_install_preserves_accounts_and_keys repeat_install
uat_case dns_records lemperctl mail dns second-uat.test
uat_case password_rotation_disable_enable password_and_disable
uat_case mutation_free_dry_run dry_run
uat_case alias_edit_deletion_and_mail_retention delete_accounts
uat_case configuration_backup lemperctl backup create
uat_case configuration_backup_verify lemperctl backup verify latest
uat_case removal_preserves_mail_and_keys remove_mail
printf 'Mail UAT: %s passed\n' "$cases"
