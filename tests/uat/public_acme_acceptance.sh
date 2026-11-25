#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Disposable Public ACME Acceptance                                |
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
[[ $(id -u) == 0 && -f /run/.containerenv && -f /run/lemper-public-uat-authorized &&
    $(cat /proc/1/comm) == systemd && $(findmnt -no OPTIONS /source) == ro,* ]] || {
    echo 'An authorized disposable public UAT container is required.' >&2
    exit 2
}
domain="${LEMPER_UAT_ACME_DOMAIN:-}"
token_file="${LEMPER_UAT_ACME_TOKEN_FILE:-/run/lemper-cloudflare-token}"
email="${LEMPER_UAT_ACME_EMAIL:-}"
[[ "$domain" =~ ^uat-[a-z0-9-]+\.[a-z0-9.-]+$ && -n "$email" &&
    -f "$token_file" && ! -L "$token_file" && $(stat -c %a "$token_file") == 600 ]] || {
    echo 'Set a reserved uat-* hostname, contact email and protected token file.' >&2
    exit 2
}
# Function-only core; no private host configuration is imported.
# shellcheck source=/dev/null
. /source/lib/core/loader.sh
is_valid_domain "$domain" || exit 2
# shellcheck source=tests/uat/helpers.bash
. /source/tests/uat/helpers.bash
uat_wait_systemd
logs=/var/log/lemper-public-uat
install -d -m 0700 "$logs" /etc/lemper /etc/letsencrypt /run/lemper-public-uat
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
lemper_load_module core/deployment
check cli_activation lemper_cli_snapshot /source
install -m 0600 /source/.env.dist /etc/lemper/lemper.conf
while IFS='|' read -r key value; do uat_profile_set /etc/lemper/lemper.conf "$key" "$value"; done <<'PROFILE'
AUTO_INSTALL|true
DRYRUN|false
FORCE_INSTALL|false
SSH_PASSWORDLESS|false
ENABLE_SWAP|false
ENCRYPT_CONFIG_AT_REST|false
ACME_REGISTER_ACCOUNT|true
ACME_WILDCARD|true
ACME_DNS_PROVIDER|"cloudflare"
ACME_DNS_PROPAGATION_WAIT|"30"
PROFILE
uat_profile_set /etc/lemper/lemper.conf SERVER_HOSTNAME "\"$domain\""
uat_profile_set /etc/lemper/lemper.conf LEMPER_ADMIN_EMAIL "\"$email\""
token=$(<"$token_file")
[[ "$token" =~ ^[a-zA-Z0-9_-]+$ ]] || exit 2
uat_profile_set /etc/lemper/lemper.conf ACME_DNS_API_TOKEN "\"$token\""
unset token
printf 'server = https://acme-staging-v02.api.letsencrypt.org/directory\n' >/etc/letsencrypt/cli.ini
check certbot_component_install lemperctl stack install certbot --yes
cert="/etc/letsencrypt/live/$domain"
function staging_issuer() { openssl x509 -in "$cert/cert.pem" -noout -issuer | grep -Fq '(STAGING)'; }
check staging_issuer staging_issuer
check base_domain_san openssl x509 -in "$cert/cert.pem" -noout -checkhost "$domain"
check wildcard_san openssl x509 -in "$cert/cert.pem" -noout -checkhost "probe.$domain"
function credential_mode() { [[ $(stat -c %a /etc/lemper/acme/dns-cloudflare.ini) == 600 ]]; }
check protected_credentials credential_mode
check renewal_dns_plugin grep -Eq '^authenticator[[:space:]]*=[[:space:]]*dns-cloudflare$' "/etc/letsencrypt/renewal/$domain.conf"
check installed_deploy_hook test -x /etc/letsencrypt/renewal-hooks/deploy/lemper-nginx.sh
install -d -m 0755 /var/www/lemper-public-uat
install -m 0644 /source/share/nginx/html/index.html /var/www/lemper-public-uat/index.html
cat >/etc/nginx/sites-available/lemper-public-uat <<VHOST
server {
    listen 443 ssl;
    server_name $domain;
    ssl_certificate $cert/fullchain.pem;
    ssl_certificate_key $cert/privkey.pem;
    root /var/www/lemper-public-uat;
    index index.html;
    add_header X-LEMPer-UAT public-acme always;
    location / { try_files \$uri \$uri/ =404; }
}
VHOST
ln -s /etc/nginx/sites-available/lemper-public-uat /etc/nginx/sites-enabled/lemper-public-uat
check nginx_configuration nginx -t
check nginx_running systemctl is-active --quiet nginx
check nginx_reload systemctl reload nginx
reload_before=$(systemctl show nginx --property=ExecReload --value)
check staging_renewal certbot renew --cert-name "$domain" --dry-run --run-deploy-hooks --no-random-sleep-on-renew
function hook_executed() {
    local current
    current=$(systemctl show nginx --property=ExecReload --value)
    [[ "$current" != "$reload_before" && "$current" == *'status=0'* ]]
}
check staging_deploy_hook hook_executed
printf 'server = https://acme-v02.api.letsencrypt.org/directory\n' >/etc/letsencrypt/cli.ini
function production_issue() {
    # Reuse the installed protected provider file; no token enters argv.
    local DRYRUN=false ACME_DNS_PROVIDER=cloudflare ACME_DNS_PROPAGATION_WAIT=30
    local LEMPER_ADMIN_EMAIL="$email"
    export DRYRUN ACME_DNS_PROVIDER ACME_DNS_PROPAGATION_WAIT LEMPER_ADMIN_EMAIL
    request_dns01_certificate "$domain" true
}
check production_issuance production_issue
check production_chain openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt \
    -untrusted "$cert/chain.pem" "$cert/cert.pem"
check production_reload systemctl reload nginx
check trusted_https curl --noproxy '*' --silent --show-error --fail --max-time 15 \
    --resolve "$domain:443:127.0.0.1" -o /run/lemper-public-uat/body "https://$domain/"
check welcome_body grep -Fq 'Your next idea' /run/lemper-public-uat/body
certificate_before=$(sha256sum "$cert/cert.pem")
reload_before=$(systemctl show nginx --property=ExecReload --value)
check production_renewal_dry_run certbot renew --cert-name "$domain" --dry-run --run-deploy-hooks --no-random-sleep-on-renew
check production_deploy_hook hook_executed
function certificate_preserved() { [[ $(sha256sum "$cert/cert.pem") == "$certificate_before" ]]; }
check renewal_keeps_live_certificate certificate_preserved
check repeat_component_install lemperctl stack install certbot --yes
check repeat_install_keeps_certificate certificate_preserved
certbot --version
openssl x509 -in "$cert/cert.pem" -noout -issuer -dates -fingerprint -sha256
printf 'Public ACME UAT: %s checks passed.\n' "$checks"
