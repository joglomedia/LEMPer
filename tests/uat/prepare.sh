#!/usr/bin/env bash
# Prepare synthetic data only inside a disposable Podman/systemd container.
set -euo pipefail
[[ "$(id -u)" -eq 0 && -f /run/.containerenv && "$(cat /proc/1/comm)" == systemd ]] || {
    echo "A disposable Podman/systemd container is required." >&2
    exit 2
}
[[ "$(findmnt -no OPTIONS /source)" == ro,* ]] || { echo "/source must be read-only." >&2; exit 2; }
installer="${LEMPER_UAT_NGINX_INSTALLER:-repo}"
[[ "$installer" == repo || "$installer" == source ]] || exit 2
install -d -m 0700 /var/log/lemper-uat /run/lemper-uat
touch /run/lemper-uat/authorized
install -d -m 0755 /checkout /checkout/tests/uat
cp -a /source/bin /source/lib /source/scripts /source/etc /source/share /source/shunit2 /checkout/
cp /source/.env.dist /source/install.sh /source/remove.sh /source/lemper.sh /source/update.sh /source/get-lemper /checkout/
cp /source/tests/uat/cli_acceptance.sh /checkout/tests/uat/
cp /checkout/.env.dist /checkout/.env
chmod 0600 /checkout/.env
ssh-keygen -q -t ed25519 -N "" -f /tmp/lemper-uat-key
LEMPER_UAT_PROFILE_INSTALLER="$installer" python3 - <<'PYTHON'
from pathlib import Path
import os, re
p=Path('/checkout/.env')
text=p.read_text()
values={
 'AUTO_INSTALL':'true', 'AUTO_REMOVE':'true', 'FORCE_INSTALL':'false',
 'FORCE_REMOVE':'false','DRYRUN':'false','ENABLE_SWAP':'false',
 'ENVIRONMENT':'"development"','SERVER_HOSTNAME':'"lemper-uat.test"',
 'SERVER_IP':'"127.0.0.1"','SERVER_PROFILE':'"small"',
 'PHP_VERSIONS':'"8.5"','PHP_FPM_MAX_CHILDREN':'4','OPCACHE_MEMORY_MB':'64',
 'LEMPER_ADMIN_EMAIL':'"uat@example.com"',
 'RSA_PUB_KEY':'"'+Path('/tmp/lemper-uat-key.pub').read_text().strip()+'"',
 'ENCRYPT_CONFIG_AT_REST':'true','INSTALL_MAILER':'false','INSTALL_SPFDKIM':'false',
 'INSTALL_POSTGRES':'true','INSTALL_MEMCACHED':'true','INSTALL_MONGODB':'false',
 'REDIS_BACKEND':'"valkey"','INSTALL_CROWDSEC':'false','INSTALL_FW':'false',
 'ACME_WILDCARD':'false','ACME_REGISTER_ACCOUNT':'false'
}
installer=os.environ['LEMPER_UAT_PROFILE_INSTALLER']
values['NGINX_INSTALLER']='"'+installer+'"'
values['INSTALL_MODSEC']='true' if installer=='repo' else 'false'
if installer=='source':
 values['NGINX_PCRE_VERSION']='""'
 for name in ('NGX_HTTP_BROTLI','NGX_HTTP_FANCYINDEX','NGX_HTTP_GEOIP',
              'NGX_HTTP_HEADERS_MORE','NGX_HTTP_IMAGE_FILTER','NGX_HTTP_SUBS_FILTER',
              'NGX_HTTP_VTS','NGX_HTTP_XSLT_FILTER','NGX_MAIL','NGX_STREAM'):
  values[name]='false'
for key,value in values.items():
 text,count=re.subn('^'+re.escape(key)+'=.*$',lambda _:key+'='+value,text,flags=re.M)
 if count!=1: raise RuntimeError('Missing/duplicate profile key: '+key)
p.write_text(text)
PYTHON
install -d -m 0700 /etc/letsencrypt
printf 'server = https://acme-staging-v02.api.letsencrypt.org/directory\n' > /etc/letsencrypt/cli.ini
chmod 0600 /etc/letsencrypt/cli.ini
echo "Synthetic UAT profile prepared. Installers and service changes stay inside this container."
