#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Disposable Public HTTP/3 Client Preparation                       |
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
[[ $(id -u) == 0 && -f /run/.containerenv && -f /run/lemper-public-client-authorized &&
    $(findmnt -no OPTIONS /source) == ro,* ]] || exit 2
grep -qx VERSION_CODENAME=resolute /etc/os-release || exit 2
work=/var/tmp/lemper-public-client
install -d -m 0700 "$work"
if [[ -x "$work/curl-8.23.0/src/curl" ]] &&
    "$work/curl-8.23.0/src/curl" --version | grep -q 'Features:.*HTTP2.*HTTP3'; then
    "$work/curl-8.23.0/src/curl" --version
    exit 0
fi
apt-get update -qq
apt-get install -y -qq build-essential curl ca-certificates libssl-dev pkg-config \
    libnghttp2-dev libnghttp3-dev libngtcp2-dev libngtcp2-crypto-ossl-dev libpsl-dev xz-utils
cd "$work"
curl -fsSL --proto '=https' --retry 3 -o curl.tar.xz \
    https://github.com/curl/curl/releases/download/curl-8_23_0/curl-8.23.0.tar.xz
printf '%s  curl.tar.xz\n' 8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5 | sha256sum -c -
tar -xJf curl.tar.xz
cd curl-8.23.0
./configure --with-openssl --with-ngtcp2 --with-nghttp3 --with-nghttp2 --disable-shared \
    --disable-manual --enable-ssls-export
make -C lib -j2 libcurl.la
make -C src -j2 curl
src/curl --version
