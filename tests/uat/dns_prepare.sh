#!/usr/bin/env bash
# Invoked by dns_cluster.sh inside a fresh primary or secondary.
set -euo pipefail
[[ $EUID == 0 && -f /run/.containerenv && $(cat /proc/1/comm) == systemd ]] || exit 2
# shellcheck source=tests/uat/helpers.bash
. /root/helpers.bash
uat_wait_systemd
role=$1 primary=$2
shift 2
case "$role" in
    primary)
        [[ $# == 2 ]]
        release=/opt/lemper/local-dnsuat
        # shellcheck source=/dev/null
        . "$release/lib/core/loader.sh"
        lemper_load_module core/deployment
        lemper_cli_activate "$release"
        profile=/etc/lemper/lemper.conf
        install -m 0600 "$release/.env.dist" "$profile"
        core_set_env_value "$profile" ENVIRONMENT development
        core_set_env_value "$profile" SERVER_IP "$primary"
        core_set_env_value "$profile" INSTALL_DNS true
        core_set_env_value "$profile" DNS_ROLE hidden
        core_set_env_value "$profile" DNS_LISTEN_IPV4 "$primary"
        core_set_env_value "$profile" DNS_TRANSFER_PEERS "$*"
        install -d -m 0700 /etc/lemper/dns-keys
        for peer in "$@"; do
            (umask 077; openssl rand -base64 32 > "/etc/lemper/dns-keys/$peer.key")
        done
        lemperctl stack install dns
        ;;
    secondary)
        [[ $# == 1 ]]
        peer=$1
        IFS= read -r key
        apt-get update -qq
        apt-get install -y -qq --no-install-recommends knot
        install -m 0640 -o root -g knot /dev/null /etc/knot/knot.conf
        cat > /etc/knot/knot.conf <<CONF
server:
    listen: $peer@53
key:
  - id: peer-${peer//./-}
    algorithm: hmac-sha256
    secret: "$key"
remote:
  - id: primary
    address: $primary
    key: peer-${peer//./-}
acl:
  - id: primary-notify
    address: $primary
    key: peer-${peer//./-}
    action: notify
zone:
  - domain: lemper-dns-uat.example
    master: primary
    acl: primary-notify
CONF
        knotc -c /etc/knot/knot.conf conf-check
        systemctl restart knot
        ;;
    *) exit 2 ;;
esac
systemctl is-active --quiet knot
