#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | Knot DNS Replication Acceptance Test                                    |
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

# Run on a disposable primary with this test zone configured on both secondaries.
set -euo pipefail
[[ ${1:-} == --disposable && $# == 4 ]] || {
    echo "Usage: dns_acceptance.sh --disposable PRIMARY SECONDARY1 SECONDARY2" >&2
    exit 2
}
primary=$2
secondaries=("$3" "$4")
domain=lemper-dns-uat.example
for host in "$primary" "${secondaries[@]}"; do
    [[ "$host" =~ ^[0-9]+(\.[0-9]+){3}$ ]] || exit 2
done
[[ $EUID == 0 && -e /etc/knot/lemper/enabled && $3 != "$4" && $2 != "$3" && $2 != "$4" ]] || exit 1
for zone in /etc/knot/lemper/published/*.conf; do
    [[ ! -f "$zone" || "${zone##*/}" == "$domain.conf" ]] || { echo "Use a dedicated test primary." >&2; exit 1; }
done
work=$(mktemp -d)
stopped=false
cleanup() {
    if [[ "$stopped" == true ]]; then lemperctl stack start dns; fi
    rm -rf -- "$work"
}
trap cleanup EXIT
revision() { lemperctl dns zone status "$domain" | awk '$1=="committed" {print $2}'; }
converged() {
    local i
    for ((i=0; i<30; i++)); do
        if lemperctl dns check "$domain" "${secondaries[@]}" "--file=$1"; then return 0; fi
        sleep 1
    done
    return 1
}
serial=$(date +%s)
cat >"$work/first" <<ZONE
\$TTL 60
@ IN SOA ns1.provider.example. hostmaster.provider.example. $serial 60 30 3600 60
@ IN NS ns1.provider.example.
@ IN NS ns2.provider.example.
@ IN A 192.0.2.14
@ IN AAAA 2001:db8::14
@ IN MX 10 mail.provider.example.
@ IN CAA 0 issue "example.net"
@ IN TXT "preserve spaces" "and strings"
ZONE
sed -e "s/$serial 60/$((serial+1)) 60/" -e 's/192.0.2.14/192.0.2.15/' "$work/first" >"$work/edit"
sed "s/$serial 60/$((serial+2)) 60/" "$work/first" >"$work/restored"
lemperctl dns zone enroll "$domain" fixture
base=$(revision)
lemperctl dns zone validate "$domain" "$work/first"
stopped=true
lemperctl stack stop dns
if lemperctl dns zone apply "$domain" "$work/first" "--base=${base:-new}"; then exit 1; fi
lemperctl dns zone status "$domain" | grep -q '^pending '
lemperctl stack start dns
stopped=false
lemperctl dns zone resume "$domain"
base=$(revision)
if lemperctl dns zone apply "$domain" "$work/edit" --base=new; then exit 1; fi
lemperctl dns zone apply "$domain" "$work/edit" "--base=$base"
converged "$work/edit"
lemperctl dns zone rollback "$domain"
converged "$work/restored"
# The primary is allowed to query but holds no secondary's transfer key.
if dig -r "@$primary" "$domain" AXFR | grep -q '[[:space:]]IN[[:space:]]SOA'; then exit 1; fi
stopped=true
lemperctl stack stop dns
converged "$work/restored"
lemperctl stack start dns
stopped=false
lemperctl dns check "$domain" "$primary" "--file=$work/restored"
lemperctl dns zone retire "$domain" "--base=$(revision)" --yes
if lemperctl dns check "$domain" "$primary"; then exit 1; fi
echo "DNS publish, replication, stale edit, rollback, primary outage and retirement passed."
