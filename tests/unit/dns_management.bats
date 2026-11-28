#!/usr/bin/env bats

load env_helper

setup() {
    unit_setup
    # Load the runtime primitives without shadowing the Bats run helper.
    . "$REAL_BASE_DIR/lib/core/validation.sh"
    . "$REAL_BASE_DIR/lib/core/execution.sh"
    lemper_load_module runtime/dns/commands
    lemper_load_module services/dns/zones
    lemper_load_module services/dns/lifecycle
    error() { echo "$*" >&2; }
    info() { echo "$*"; }
}

@test "external DNS planning requires neither a local daemon nor delegated authority" {
    run lemper_dns_command plan SHOP.Example. --ipv4=192.0.2.10
    [ "$status" = 0 ]
    [ "$output" = 'shop.example. IN A 192.0.2.10' ]
    run lemper_dns_command plan shop.example --ipv4=300.0.0.1
    [ "$status" != 0 ]
    run lemper_dns_command zone enroll '../shop' customer
    [ "$status" != 0 ]
}

@test "DNS serial arithmetic handles wraparound and rejects ambiguous or repeated revisions" {
    lemper_dns_newer 0 4294967295
    ! lemper_dns_newer 4294967295 0
    ! lemper_dns_newer 123 123
    ! lemper_dns_newer 2147483648 0
}

@test "hidden DNS requires distinct peers and restricts inbound UDP and TCP to their addresses" {
    lemper_load_module services/firewall/nftables
    INSTALL_DNS=true DNS_ROLE=hidden DNS_LISTEN_IPV4=192.0.2.1 DNS_TRANSFER_PEERS='192.0.2.2 192.0.2.3'
    run lemper_nft_rules
    [ "$status" = 0 ]
    [[ "$output" == *'ip saddr 192.0.2.2 ip daddr 192.0.2.1 meta l4proto { udp, tcp } th dport 53 accept'* ]]
    [[ "$output" != *$'\n  ip daddr 192.0.2.1 '* ]]
    ! DNS_TRANSFER_PEERS='192.0.2.2 192.0.2.2' lemper_dns_network
    ! DNS_TRANSFER_PEERS='' lemper_dns_network
    ! DNS_LISTEN_IPV4='0.0.0.0' lemper_dns_network
    DNS_ROLE=local DNS_LISTEN_IPV4=127.0.0.1 DNS_TRANSFER_PEERS=''
    run lemper_nft_rules
    [ "$status" = 0 ]
    [[ "$output" != *'dport 53'* ]]
}

@test "DNS verification requires authoritative answers and matching SOA on both transports" {
    dig() {
        local serial=7 flags='qr aa'
        [[ " $* " != *' +tcp '* ]] || serial=8
        [[ " $* " != *' @ns2.example '* ]] || flags='qr ra'
        printf ';; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1\n;; flags: %s; QUERY: 1\n' "$flags"
        echo "shop.example. 60 IN SOA ns.example. mail.example. $serial 60 30 3600 60"
    }
    run lemper_dns_command check shop.example ns1.example
    [ "$status" != 0 ]
    [[ "$output" == *'SOA 7'* && "$output" == *'SOA 8'* ]]
    run lemper_dns_command check shop.example ns2.example
    [ "$status" != 0 ]
    [[ "$output" == *'No authoritative SOA'* ]]
}

@test "zone compilation preserves TXT values and isolates include paths from the host" {
    command -v named-compilezone >/dev/null || skip "bind9-utils required"
    cat > "$TEST_TMPDIR/source" <<'ZONE'
$TTL 300
@ IN SOA ns.shop.example. hostmaster.shop.example. ( 1 60 30 3600 60 )
@ IN NS ns.shop.example.
ns IN A 192.0.2.10
@ IN TXT "one   two" "three"
ZONE
    run lemper_dns_command plan shop.example "$TEST_TMPDIR/source"
    [ "$status" = 0 ]
    [[ "$output" == *'"one   two" "three"'* ]]
    printf '@ IN TXT "outside"\n' > "$TEST_TMPDIR/other"
    printf '$INCLUDE %s\n' "$TEST_TMPDIR/other" >> "$TEST_TMPDIR/source"
    run lemper_dns_command plan shop.example "$TEST_TMPDIR/source"
    [ "$status" != 0 ]
    [[ "$output" != *'"outside"'* ]]
}
