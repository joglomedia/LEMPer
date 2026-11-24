#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Disposable HTTP-01 Preparation                                |
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
    $(cat /proc/1/comm) == systemd && $(findmnt -no OPTIONS /release) == ro,* ]] || {
    echo 'An authorized disposable HTTP-01 UAT container is required.' >&2
    exit 2
}
domain="${LEMPER_UAT_HTTP01_DOMAIN:-}"
[[ "$domain" == lemper.eu.org ]] || { echo 'Use the designated HTTP-01 domain.' >&2; exit 2; }
[[ ! -e "/etc/nginx/sites-available/$domain.conf" && ! -e "/etc/letsencrypt/live/$domain" ]] || exit 2
logs=/var/log/lemper-http01-uat
install -d -m 0700 "$logs" /etc/letsencrypt
read -r checksum _ </release/lemper-v4.0.0.tar.gz.sha256
bash /release/get-lemper --version 4.0.0 --archive /release/lemper-v4.0.0.tar.gz --sha256 "$checksum" >"$logs/bootstrap.log" 2>&1
# shellcheck source=/dev/null
. /opt/lemper/current/tests/uat/helpers.bash
uat_wait_systemd
apt-get update -qq >"$logs/bridge-dependency.log" 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -qq -y inotify-tools >>"$logs/bridge-dependency.log" 2>&1
# The fixture's internal kernel hostname is private during package preparation.
while IFS='|' read -r key value; do uat_profile_set /etc/lemper/lemper.conf "$key" "$value"; done <<'PROFILE'
AUTO_INSTALL|true
INSTALL_CERTBOT|true
SSH_PASSWORDLESS|false
ENABLE_SWAP|false
ENVIRONMENT|"development"
ACME_REGISTER_ACCOUNT|false
ACME_WILDCARD|false
DRYRUN|false
PROFILE
uat_profile_set /etc/lemper/lemper.conf SERVER_HOSTNAME "\"$(hostname)\""
cat >/etc/letsencrypt/cli.ini <<'CERTBOT'
server = https://acme-staging-v02.api.letsencrypt.org/directory
register-unsafely-without-email = true
CERTBOT
lemperctl stack install certbot --yes >"$logs/component-install.log" 2>&1
uat_profile_set /etc/lemper/lemper.conf ENVIRONMENT '"production"'
certbot --version
install -d -m 0755 /var/www/lemper-http01 /etc/nginx/ssl
printf 'LEMPer isolated HTTP-01 application\n' >/var/www/lemper-http01/index.html
chmod 0644 /var/www/lemper-http01/index.html
cat >"/etc/nginx/sites-available/$domain.conf" <<'NGINX'
server {
    listen 80;
    listen [::]:80;
    server_name lemper.eu.org;
    set $root_path "/var/www/lemper-http01";
    root $root_path;
    #ssl_certificate /etc/letsencrypt/live/lemper.eu.org/fullchain.pem;
    #ssl_certificate_key /etc/letsencrypt/live/lemper.eu.org/privkey.pem;
    location / { try_files $uri $uri/ =404; }
}
NGINX
ln -s "/etc/nginx/sites-available/$domain.conf" "/etc/nginx/sites-enabled/$domain.conf"
nginx -t >"$logs/nginx-before.log" 2>&1
systemctl start nginx
# Pause real webroot challenges while the operator copies only public challenge
# values to the existing production webroot. No SSH credentials enter this fixture.
cat >/usr/local/bin/certbot <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
args=()
for argument in "$@"; do
    [[ "$argument" != --noninteractive && "$argument" != --non-interactive ]] || continue
    args+=("$argument")
done
exec /opt/certbot/bin/certbot "${args[@]}" --debug-challenges
WRAPPER
chmod 0755 /usr/local/bin/certbot
printf 'READY_FOR_INTERACTIVE_WEBROOT_CHALLENGE\n'
