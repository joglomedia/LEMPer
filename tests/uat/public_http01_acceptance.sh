#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Disposable HTTP-01 Verification                                |
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
umask 077
[[ $(id -u) == 0 && -f /run/.containerenv && -f /run/lemper-http01-uat-authorized &&
    $(cat /proc/1/comm) == systemd ]] || exit 2
domain="${LEMPER_UAT_HTTP01_DOMAIN:-}"
[[ "$domain" == lemper.eu.org ]] || exit 2
cert="/etc/letsencrypt/live/$domain"
logs=/var/log/lemper-http01-uat
install -d -m 0700 "$logs"
checks=0
function check() {
    local name="$1" status
    shift
    set +e
    (set -e; "$@") >"$logs/$name.log" 2>&1
    status=$?
    set -e
    [[ "$status" == 0 ]] || { printf 'FAIL %s (private log: %s/%s.log)\n' "$name" "$logs" "$name"; exit 1; }
    checks=$((checks + 1))
    printf 'PASS %s\n' "$name"
}
function staging() { openssl x509 -in "$cert/cert.pem" -noout -issuer | grep -Fq '(STAGING)'; }
function body() {
    curl --noproxy '*' --silent --show-error --fail --max-time 10 --cacert "$cert/fullchain.pem" \
        --resolve "$domain:443:127.0.0.1" "https://$domain/" >"$logs/body"
    grep -qx 'LEMPer isolated HTTP-01 application' "$logs/body"
}
function rejects_wrong_hostname() {
    local status=0
    if curl --noproxy '*' --silent --show-error --fail --max-time 10 --cacert "$cert/fullchain.pem" \
        --resolve wrong-http01.test:443:127.0.0.1 https://wrong-http01.test/; then return 1; else status=$?; fi
    [[ "$status" == 60 ]]
}
function rejects_untrusted_staging() {
    local status=0
    if curl --noproxy '*' --silent --show-error --fail --max-time 10 \
        --resolve "$domain:443:127.0.0.1" "https://$domain/"; then return 1; else status=$?; fi
    [[ "$status" == 60 ]]
}
function snapshot() {
    sha256sum "$cert/cert.pem" >/run/http01-certificate-before
    systemctl show nginx --property=ExecReload --value >/run/http01-reload-before
}
function deploy_hook_executed() {
    local current before
    current=$(systemctl show nginx --property=ExecReload --value)
    before=$(</run/http01-reload-before)
    [[ "$current" != "$before" && "$current" == *'status=0'* ]]
}
case "${1:-}" in
    --before-renewal)
        check staging_issuer staging
        check domain_san openssl x509 -in "$cert/cert.pem" -noout -checkhost "$domain"
        check certificate_expiry openssl x509 -in "$cert/cert.pem" -noout -checkend 86400
        check webroot_authenticator grep -Eq '^authenticator[[:space:]]*=[[:space:]]*webroot$' "/etc/letsencrypt/renewal/$domain.conf"
        check installed_deploy_hook test -x /etc/letsencrypt/renewal-hooks/deploy/lemper-nginx.sh
        check nginx_configuration nginx -t
        check staging_https_and_body body
        check wrong_hostname_rejected rejects_wrong_hostname
        check untrusted_staging_rejected rejects_untrusted_staging
        check renewal_snapshot snapshot
        ;;
    --after-renewal)
        check successful_real_renewal test -f /run/http01-renewal-succeeded
        check renewal_preserves_certificate sha256sum -c /run/http01-certificate-before
        check deploy_hook_executed deploy_hook_executed
        check renewed_nginx_configuration nginx -t
        check renewed_https_and_body body
        check renewed_wrong_hostname_rejected rejects_wrong_hostname
        check renewed_untrusted_staging_rejected rejects_untrusted_staging
        ;;
    *) echo 'Use --before-renewal or --after-renewal.' >&2; exit 2 ;;
esac
printf 'HTTP-01 verification: %s checks passed.\n' "$checks"
