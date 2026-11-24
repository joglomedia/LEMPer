#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Disposable Protocol Fixture Preparation                          |
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
[[ $(id -u) == 0 && -f /run/.containerenv && $(cat /proc/1/comm) == systemd &&
    $(findmnt -no OPTIONS /source) == ro,* ]] || exit 2
grep -qx 'VERSION_CODENAME=resolute' /etc/os-release || {
    echo 'Use the Ubuntu 26.04 fixture for the OpenSSL/ngtcp2 client build.' >&2
    exit 2
}
# shellcheck source=tests/uat/helpers.bash
. /source/tests/uat/helpers.bash
uat_wait_systemd
install -d -m 0700 /run/lemper-protocols /var/log/lemper-protocols
touch /run/lemper-protocols-authorized
apt-get update -qq
apt-get install -y -qq build-essential curl ca-certificates libpcre2-dev zlib1g-dev \
    libssl-dev pkg-config libnghttp3-dev libngtcp2-dev libngtcp2-crypto-ossl-dev libpsl-dev xz-utils
cd /run/lemper-protocols
curl -fsSL --proto '=https' --retry 3 -o curl.tar.xz \
    https://github.com/curl/curl/releases/download/curl-8_23_0/curl-8.23.0.tar.xz
printf '%s  curl.tar.xz\n' 8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5 | sha256sum -c -
tar -xJf curl.tar.xz
cd curl-8.23.0
# Session export is an experimental client feature used only for this UAT.
./configure --with-openssl --with-ngtcp2 --with-nghttp3 --disable-shared \
    --disable-manual --enable-ssls-export
make -C lib -j2 libcurl.la
make -C src -j2 curl
src/curl --version
# shellcheck source=/dev/null
. /source/lib/core/loader.sh
lemper_load_module services/nginx/ssl_builders
lemper_load_module services/nginx/build
export DRYRUN=false RED=31 GREEN=32 YELLOW=33 BLUE=34
export LEMPER_OPERATION_LOCK=/run/lemper-protocols/operation.lock
function run() { lemper_exec "$@"; }
function get_cpu_cores() { echo 2; }
function prepare_nginx() {
    local NGINX_BUILD_DIR=/var/tmp/lemper-protocols-source NGINX_HTTP3=true
    export NGINX_BUILD_DIR NGINX_HTTP3
    local NGINX_RELEASE_VERSION=1.30.8 NGINX_SRC_DIR="" NGX_CONFIGURE_ARGS=()
    build_openssl openssl-3.5.9 || return 1
    download_nginx_source "$NGINX_RELEASE_VERSION" || return 1
    NGX_CONFIGURE_ARGS+=(--prefix=/run/lemper-protocols/nginx --with-http_ssl_module --with-http_v2_module)
    configure_nginx || return 1
    lemper_exec make -C "$NGINX_SRC_DIR" -j2 || return 1
    "$NGINX_SRC_DIR/objs/nginx" -V
}
# One callback keeps the builder's request state within the locked operation.
lemper_with_lock prepare_nginx
