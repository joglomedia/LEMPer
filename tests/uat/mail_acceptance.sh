#!/usr/bin/env bash
# System-changing mail UAT: only a designated disposable Podman/systemd container.
set -euo pipefail
[[ $(id -u) == 0 && -f /run/.containerenv && -f /run/lemper-mail-uat-authorized &&
   $(cat /proc/1/comm) == systemd ]] || { echo 'Designated mail UAT container required.' >&2; exit 2; }
[[ $(findmnt -no OPTIONS /source) == ro,* ]] || exit 2
logs=/var/log/lemper-mail-uat
install -d -m 0700 "$logs" /checkout /run/mail-uat
cp -a /source/bin /source/lib /source/scripts /source/etc /source/share /checkout/
cp /source/.env.dist /checkout/.env
chmod 0600 /checkout/.env
python3 - <<'PY'
from pathlib import Path
import re
p=Path('/checkout/.env')
s=p.read_text()
values={'AUTO_INSTALL':'true', 'INSTALL_MAILER':'true','INSTALL_SPFDKIM':'true',
        'FORCE_INSTALL':'false','ENVIRONMENT':'"development"','SERVER_HOSTNAME':'"mail.lemper-uat.test"',
        'SERVER_IP':'"127.0.0.1"','SENDER_DOMAIN':'"first-uat.test"','MAILER_HOSTNAME':'"mail.lemper-uat.test"',
        'MAILER_CERT_PATH':'"/run/mail-uat/tls"','SSH_PASSWORDLESS':'false'}
for k,v in values.items():
 s,n=re.subn('^'+k+'=.*$',lambda _:k+'='+v,s,flags=re.M)
 assert n==1,k
p.write_text(s)
PY
install -d -m 0700 /run/mail-uat/tls
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=Mail-UAT-CA \
    -keyout /run/mail-uat/ca.key -out /run/mail-uat/ca.pem > "$logs/certificates.log" 2>&1
openssl req -new -newkey rsa:2048 -nodes -subj /CN=mail.lemper-uat.test \
    -keyout /run/mail-uat/tls/privkey.pem -out /run/mail-uat/mail.csr >> "$logs/certificates.log" 2>&1
printf 'subjectAltName=DNS:mail.lemper-uat.test\nextendedKeyUsage=serverAuth\n' > /run/mail-uat/extensions
openssl x509 -req -in /run/mail-uat/mail.csr -CA /run/mail-uat/ca.pem -CAkey /run/mail-uat/ca.key \
    -CAcreateserial -days 2 -extfile /run/mail-uat/extensions -out /run/mail-uat/tls/fullchain.pem >> "$logs/certificates.log" 2>&1
chmod 0600 /run/mail-uat/tls/privkey.pem
printf '\n127.0.0.1 mail.lemper-uat.test\n' >> /etc/hosts
python3 - <<'PY'
from pathlib import Path
import secrets
for name in ('password','replacement'):
 p=Path('/run/mail-uat/'+name)
 p.write_text(secrets.token_urlsafe(30)+'\n');p.chmod(0o600)
PY
cases=0
function uat_case() {
    local name="$1"
    shift
    cases=$((cases+1))
    if "$@" > "$logs/$name.log" 2>&1; then printf 'PASS %s\n' "$name";
    else printf 'FAIL %s (log: %s)\n' "$name" "$logs/$name.log"; exit 1; fi
}
function install_mail() { bash /checkout/scripts/install_mailer.sh; }
function activate_cli() {
    bash -c '
        . /checkout/lib/core/loader.sh
        . /checkout/lib/core/deployment.sh
        lemper_cli_snapshot /checkout
    '
    install -m 0600 /checkout/.env /etc/lemper/lemper.conf
}
function services() {
    systemctl is-active --quiet postfix dovecot opendkim
    test -S /var/spool/postfix/private/auth
    test -S /var/spool/postfix/private/dovecot-lmtp
    lemperctl mail check
}
function repeat_install() {
    local before after
    before=$(sha256sum /etc/lemper-mail/keys/first-uat.test/lemper.private /etc/lemper-mail/current/accounts)
    install_mail
    after=$(sha256sum /etc/lemper-mail/keys/first-uat.test/lemper.private /etc/lemper-mail/current/accounts)
    [[ "$before" == "$after" ]]
}
function delivery() {
    python3 - <<'PY'
import imaplib,smtplib,ssl,time,subprocess
from pathlib import Path
ctx=ssl.create_default_context(cafile='/run/mail-uat/ca.pem')
pw=Path('/run/mail-uat/password').read_text().strip()
run_id=str(time.time_ns())
primary='LEMPer mail UAT '+run_id
secondary='Second domain UAT '+run_id
incoming='Incoming UAT '+run_id
remote_ip=subprocess.check_output(['hostname','-I'],text=True).split()[0]
with smtplib.SMTP(remote_ip,25,timeout=10,source_address=(remote_ip,0)) as s:
 s.ehlo();assert not s.has_extn('auth')
 assert s.mail('probe@first-uat.test')[0]==250
 assert s.rcpt('nobody@first-uat.test')[0]>=500
 # This reserved domain avoids delivery or a remote network dependency.
 assert s.rcpt('outsider@example.net')[0]>=500
with smtplib.SMTP('mail.lemper-uat.test',587,timeout=10) as s:
 s.ehlo();assert not s.has_extn('auth')
 assert s.mail('alice@first-uat.test')[0]>=500
 s.starttls(context=ctx);s.ehlo();s.login('alice@first-uat.test',pw)
 s.mail('bob@second-uat.test')
 assert s.rcpt('alice@first-uat.test')[0]>=500  # reject sender impersonation at RCPT
 s.rset()
 s.sendmail('alice@first-uat.test','team@second-uat.test',
            'From: alice@first-uat.test\r\nTo: team@second-uat.test\r\nSubject: '+primary+'\r\n\r\nVirtual delivery\r\n')
for attempt in range(50):
 with imaplib.IMAP4_SSL('mail.lemper-uat.test',993,ssl_context=ctx) as m:
  m.login('bob@second-uat.test',pw);m.select('INBOX')
  typ,data=m.search(None,'SUBJECT','"'+primary+'"')
  if data[0]:
   typ,msg=m.fetch(data[0].split()[-1],'(RFC822)')
   assert b'DKIM-Signature:' in msg[0][1]
   assert b'd=first-uat.test' in msg[0][1]
   break
 time.sleep(.2)
else: raise RuntimeError('LMTP delivery to second domain did not arrive')
# Send as the second domain and receive mail from an untrusted network client.
with smtplib.SMTP('mail.lemper-uat.test',587,timeout=10) as s:
 s.starttls(context=ctx);s.ehlo();s.login('bob@second-uat.test',pw)
 s.sendmail('bob@second-uat.test','alice@first-uat.test',
            'From: bob@second-uat.test\r\nTo: alice@first-uat.test\r\nSubject: '+secondary+'\r\n\r\nSecond signer\r\n')
with smtplib.SMTP(remote_ip,25,timeout=10,source_address=(remote_ip,0)) as s:
 s.sendmail('remote@outside-uat.test','team@second-uat.test',
            'From: remote@outside-uat.test\r\nTo: team@second-uat.test\r\nSubject: '+incoming+'\r\n\r\nRemote delivery\r\n')
for account,subject,signer in [('alice@first-uat.test',secondary,b'd=second-uat.test'),
                               ('bob@second-uat.test',incoming,None)]:
 for attempt in range(50):
  with imaplib.IMAP4_SSL('mail.lemper-uat.test',993,ssl_context=ctx) as m:
   m.login(account,pw);m.select('INBOX');typ,data=m.search(None,'SUBJECT','"'+subject+'"')
   if data[0]:
    if signer:
     typ,msg=m.fetch(data[0].split()[-1],'(RFC822)');assert signer in msg[0][1]
    break
  time.sleep(.2)
 else:raise RuntimeError('Mail was not delivered: '+subject)
# SMTP STARTTLS receive and IMAP STARTTLS use the same validated certificate.
with smtplib.SMTP('mail.lemper-uat.test',25,timeout=10) as s:s.starttls(context=ctx)
with imaplib.IMAP4('mail.lemper-uat.test',143) as m:
 m.starttls(ssl_context=ctx);m.login('bob@second-uat.test',pw)
PY
}
function literal_address() {
    lemperctl mail account add tag+literal@first-uat.test --password-file /run/mail-uat/password
    python3 - <<'PY'
import imaplib,smtplib,ssl,time
from pathlib import Path
ctx=ssl.create_default_context(cafile='/run/mail-uat/ca.pem')
pw=Path('/run/mail-uat/password').read_text().strip()
subject='Literal plus '+str(time.time_ns())
with smtplib.SMTP('mail.lemper-uat.test',587,timeout=10) as s:
 s.starttls(context=ctx);s.ehlo();s.login('tag+literal@first-uat.test',pw)
 s.sendmail('tag+literal@first-uat.test','tag+literal@first-uat.test',
            'From: tag+literal@first-uat.test\r\nTo: tag+literal@first-uat.test\r\nSubject: '+subject+'\r\n\r\nLiteral plus address\r\n')
for attempt in range(50):
 with imaplib.IMAP4_SSL('mail.lemper-uat.test',993,ssl_context=ctx) as m:
  m.login('tag+literal@first-uat.test',pw);m.select('INBOX')
  typ,data=m.search(None,'SUBJECT','"'+subject+'"')
  if data[0]:break
 time.sleep(.2)
else:raise RuntimeError('literal plus-address delivery failed')
assert Path('/var/vmail/first-uat.test/tag+literal/Maildir').is_dir()
assert not Path('/var/vmail/first-uat.test/tag/Maildir').exists()
PY
    lemperctl mail account delete tag+literal@first-uat.test --purge --yes
}
function password_and_disable() {
    lemperctl mail account edit alice@first-uat.test --password-file /run/mail-uat/replacement
    python3 - <<'PY'
import imaplib,ssl
from pathlib import Path
ctx=ssl.create_default_context(cafile='/run/mail-uat/ca.pem')
with imaplib.IMAP4_SSL('mail.lemper-uat.test',993,ssl_context=ctx) as m:
 try:m.login('alice@first-uat.test',Path('/run/mail-uat/password').read_text().strip())
 except imaplib.IMAP4.error:pass
 else:raise RuntimeError('old password still authenticates')
 m.login('alice@first-uat.test',Path('/run/mail-uat/replacement').read_text().strip())
PY
    python3 - <<'PY'
import imaplib,ssl,subprocess
from pathlib import Path
ctx=ssl.create_default_context(cafile='/run/mail-uat/ca.pem')
m=imaplib.IMAP4_SSL('mail.lemper-uat.test',993,ssl_context=ctx)
m.login('alice@first-uat.test',Path('/run/mail-uat/replacement').read_text().strip())
subprocess.run(['lemperctl','mail','account','edit','alice@first-uat.test','--disable'],check=True)
try:m.noop()
except (imaplib.IMAP4.abort,OSError):pass
else:raise RuntimeError('disabled mailbox session was not disconnected')
m.shutdown()
PY
    python3 - <<'PY'
import imaplib,ssl
from pathlib import Path
ctx=ssl.create_default_context(cafile='/run/mail-uat/ca.pem')
with imaplib.IMAP4_SSL('mail.lemper-uat.test',993,ssl_context=ctx) as m:
 try:m.login('alice@first-uat.test',Path('/run/mail-uat/replacement').read_text().strip())
 except imaplib.IMAP4.error:pass
 else:raise RuntimeError('disabled account still authenticates')
PY
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
