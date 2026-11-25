#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Disposable Public Protocol Acceptance                            |
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
[[ $(id -u) == 0 && -f /run/.containerenv && -f /run/lemper-public-client-authorized &&
    $(findmnt -no OPTIONS /source) == ro,* ]] || exit 2
domain="${LEMPER_UAT_ACME_DOMAIN:-}"
port="${LEMPER_UAT_PUBLIC_PORT:-18443}"
[[ "$domain" =~ ^uat-[a-z0-9-]+\.[a-z0-9.-]+$ &&
    "$port" =~ ^[1-9][0-9]{3,4}$ && "$port" -ge 1024 && "$port" -le 65535 ]] || exit 2
# shellcheck source=/dev/null
. /source/lib/core/loader.sh
is_valid_domain "$domain" || exit 2
work=/var/tmp/lemper-public-client
client="$work/curl-8.23.0/src/curl"
[[ -x "$client" ]] || exit 2
logs="$work/acceptance"
install -d -m 0700 "$logs"
url="https://$domain:$port/"
ip=$(getent ahostsv4 "$domain" | awk 'NR == 1 {print $1}')
[[ $(validate_ipv4 "$ip") == true ]] || exit 2
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
function client_features() { "$client" --version | grep -q 'Features:.*HTTP2.*HTTP3'; }
check client_features client_features
common=(-q -4 --noproxy '*' --silent --show-error --fail --max-time 20)
check public_https "$client" "${common[@]}" --http1.1 -o "$work/http1.body" -w '%{http_version} %{response_code}\n' "$url"
check https_metadata grep -qx '1.1 200' "$logs/public_https.log"
check public_http2 "$client" "${common[@]}" --http2 -o /dev/null -w '%{http_version} %{response_code}\n' "$url"
check http2_metadata grep -qx '2 200' "$logs/public_http2.log"
check public_quic "$client" "${common[@]}" --http3-only --ssl-sessions "$work/public.sessions" \
    -D "$work/public.headers" -o "$work/public.body" \
    -w '%{http_version} %{response_code} %{tls_earlydata}\n' "$url"
check quic_metadata grep -qx '3 200 0' "$logs/public_quic.log"
check welcome_body grep -Fq 'Your next idea' "$work/public.body"
check fixture_identity grep -Fiq 'X-LEMPer-UAT: public-protocol' "$work/public.headers"
check advertised_public_port grep -Fiq "Alt-Svc: h3=\":$port\"" "$work/public.headers"
check disabled_early_data "$client" "${common[@]}" --http3-only --tls-earlydata \
    --ssl-sessions "$work/public.sessions" -o /dev/null \
    -w '%{http_version} %{response_code} %{tls_earlydata}\n' "$url"
check early_data_metadata grep -qx '3 200 0' "$logs/disabled_early_data.log"
check tls12_https "$client" "${common[@]}" --http1.1 --tlsv1.2 --tls-max 1.2 \
    -o /dev/null -w '%{http_version} %{response_code}\n' "$url"
check tls12_metadata grep -qx '1.1 200' "$logs/tls12_https.log"
function hostname_rejected() {
    local status=0
    "$client" "${common[@]}" --http3-only --resolve "wrong.lemper-uat.test:$port:$ip" \
        "https://wrong.lemper-uat.test:$port/" >/dev/null 2>&1 || status=$?
    [[ "$status" == 60 ]]
}
check hostname_mismatch hostname_rejected
check unrelated_trust_anchor openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -keyout "$work/untrusted.key" -out "$work/untrusted.crt" -subj /CN=unrelated.lemper-uat.test
install -d -m 0700 "$work/empty-ca-path"
function untrusted_rejected() {
    local status=0
    "$client" "${common[@]}" --http3-only --cacert "$work/untrusted.crt" --capath "$work/empty-ca-path" \
        "$url" >/dev/null 2>&1 || status=$?
    [[ "$status" == 60 ]]
}
check unrelated_ca_rejected untrusted_rejected
rm -f -- "$work/untrusted.key"
printf 'Public protocol UAT: %s checks passed.\n' "$checks"
