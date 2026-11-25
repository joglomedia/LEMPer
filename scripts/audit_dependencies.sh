#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Package and Source Dependency Audit                              |
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


# Read-only review of installed package candidates and public source pins.
set -e -o pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
echo "Installed packages and candidates from configured APT repositories"
for package in nginx mariadb-server redis-server valkey-server postgresql memcached certbot crowdsec fail2ban; do
    apt-cache policy "${package}" 2>/dev/null || true
done
echo
echo "Public source/version settings requiring upstream maintenance review"
# Read only the public defaults and a fixed allow-list; never print private config.
awk -F= '$1 ~ /^(NGINX_CUSTOMSSL_VERSION|NGINX_PCRE_VERSION|MYSQL_VERSION|DEFAULT_PHP_VERSION|MONGODB_VERSION|POSTGRES_VERSION|BUNJS_VERSION|FTP_SERVER_VERSION|CROWDSEC_VERSION|ADMINER_VERSION)$/ {print}' "${root}/.env.dist"
echo
echo "Pending package upgrades (simulation; no installation)"
apt-get -s upgrade
