#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Shared Security Helpers                                          |
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



function lemper_nft_rules() {
    local ports="${LEMPER_SSH_ALLOWED_PORTS:-${SSH_PORT:-22}}" port tcp=(80 443 8082 8083) ssh=()
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        local active_port="${SSH_CONNECTION##* }"
        [[ "$active_port" =~ ^[0-9]{1,5}$ ]] || return 1
        ports="$ports,$active_port"
    fi
    IFS=, read -r -a ssh <<< "$ports"
    [[ ${#ssh[@]} -gt 0 && ${#ssh[@]} -le 20 ]] || return 1
    for port in "${ssh[@]}"; do
        [[ "$port" =~ ^[0-9]{1,5}$ ]] || { error "Invalid SSH firewall port."; return 1; }
        ((10#$port > 0 && 10#$port <= 65535)) || { error "Invalid SSH firewall port."; return 1; }
        tcp+=("$((10#$port))")
    done
    [[ "${INSTALL_MAILER:-false}" != true ]] || tcp+=(25 465 587 993)
    [[ "${MYSQL_ALLOW_REMOTE:-false}" != true ]] || tcp+=(3306)
    if [[ "${INSTALL_FTP_SERVER:-false}" == true ]]; then
        local minimum="${FTP_MIN_PORT:-45000}" maximum="${FTP_MAX_PORT:-45099}"
        [[ "$minimum" =~ ^[0-9]{1,5}$ && "$maximum" =~ ^[0-9]{1,5}$ ]] &&
            ((10#$minimum > 0 && 10#$maximum <= 65535 && 10#$minimum <= 10#$maximum)) || return 1
        tcp+=(21 "$((10#$minimum))-$((10#$maximum))")
    fi
    # add/delete in one atomic transaction replaces only LEMPer's own table.
    printf 'add table inet lemper
delete table inet lemper
table inet lemper {
'
    printf ' chain input { type filter hook input priority 0; policy drop;
'
    printf '  iifname "lo" accept
  ct state established,related accept
  ct state invalid drop
'
    printf '  meta l4proto { icmp, ipv6-icmp } accept
  tcp dport { '
    local joined
    joined=$(IFS=,; printf '%s' "${tcp[*]}")
    printf '%s } accept\n' "$joined"
    [[ "${NGINX_HTTP3:-false}" != true ]] || printf '  udp dport 443 accept\n'
    if [[ "${INSTALL_DNS:-false}" == true ]]; then
        lemper_load_module services/dns/lifecycle && lemper_dns_network || return 1
        local address="${DNS_LISTEN_IPV4:-127.0.0.1}" peer peers=()
        case "${DNS_ROLE:-local}" in
            public) printf '  ip daddr %s meta l4proto { udp, tcp } th dport 53 accept\n' "$address" ;;
            hidden)
                read -r -a peers <<< "$DNS_TRANSFER_PEERS"
                for peer in "${peers[@]}"; do
                    printf '  ip saddr %s ip daddr %s meta l4proto { udp, tcp } th dport 53 accept\n' "$peer" "$address"
                done ;;
        esac
    fi
    printf ' }\n}\n'
}

function lemper_nft_apply_policy() {
    local migrate="${1:-false}" root=/etc/lemper/firewall temporary ufw_active=false
    if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q '^Status: active'; then ufw_active=true; fi
    if [[ "$ufw_active" == true && "$migrate" != true ]]; then
        error "UFW is active. Use firewall apply --migrate-from-ufw for an explicit backed-up migration."; return 1
    fi
    if command -v csf >/dev/null || command -v apf >/dev/null; then
        error "Remove or migrate CSF/APF explicitly before selecting native nftables."; return 1
    fi
    if [[ "${DRYRUN:-false}" == true ]]; then lemper_nft_rules >/dev/null || return 1; info "Would apply only inet lemper firewall rules."; return 0; fi
    [[ ! -L "$root" ]] || return 1
    install -d -m 0700 "$root" || return 1
    if [[ ! -f "$root/managed" ]] && { [[ -e "$root/current.nft" ]] || nft list table inet lemper >/dev/null 2>&1; }; then
        error "Refusing to replace an unmanaged inet lemper table/configuration."; return 1
    fi
    temporary=$(mktemp "$root/.rules.XXXXXXXX") || return 1
    if ! lemper_nft_rules > "$temporary" || ! nft -c -f "$temporary"; then rm -f "$temporary"; return 1; fi
    if [[ -f "$root/pending" ]]; then rm -f "$temporary"; error "Confirm or roll back the pending firewall change first."; return 1; fi
    local old
    old=$(nft list table inet lemper 2>/dev/null) || old=""
    printf '%s\n' "$old" > "$root/previous.nft" || return 1
    if [[ -f "$root/current.nft" ]]; then cp -p "$root/current.nft" "$root/previous-config.nft" || return 1; else rm -f "$root/previous-config.nft"; fi
    printf '%s\n' "$ufw_active" > "$root/previous-ufw" || return 1
    touch "$root/pending"
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        # Arm recovery before the rule change; confirmation requires a successful new login.
        local module template
        module=$(readlink -f "${BASH_SOURCE[0]}") || return 1
        template="$(dirname "$module")/../../../etc/lemper/firewall-recovery.sh"
        lemper_exec install -m0600 "$module" "$root/recovery-driver.sh" || return 1
        lemper_exec install -m0700 "$template" "$root/recover" || return 1
        lemper_exec systemd-run --unit=lemper-firewall-rollback --on-active=2m "$root/recover" || { rm -f "$root/pending" "$temporary"; return 1; }
    fi
    if ! lemper_exec nft -f "$temporary"; then
        rm -f "$temporary"; lemper_nft_rollback_policy; return 1
    fi
    if [[ "$ufw_active" == true ]] && ! lemper_exec ufw disable; then
        rm -f "$temporary"; lemper_nft_rollback_policy; return 1
    fi
    chmod 0600 "$temporary" || return 1
    mv -T "$temporary" "$root/current.nft" || return 1
    cat > /etc/systemd/system/lemper-nftables.service <<'UNIT'
[Unit]
Description=LEMPer scoped inet firewall
Before=network-pre.target
Wants=network-pre.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/lemper/firewall/current.nft
ExecReload=/usr/sbin/nft -f /etc/lemper/firewall/current.nft
[Install]
WantedBy=multi-user.target
UNIT
    if ! systemd-analyze verify /etc/systemd/system/lemper-nftables.service ||
       ! lemper_exec systemctl daemon-reload || ! lemper_exec systemctl enable lemper-nftables.service || ! lemper_exec systemctl start lemper-nftables.service; then
        lemper_nft_rollback_policy; return 1
    fi
    if [[ -z "${SSH_CONNECTION:-}" ]]; then lemper_nft_confirm_policy; else
        info "Firewall recovery is armed for two minutes; confirm from a working new SSH session."
    fi
}
function lemper_nft_confirm_policy() {
    if [[ "${DRYRUN:-false}" == true ]]; then info "Would confirm pending firewall rules."; return 0; fi
    [[ -f /etc/lemper/firewall/pending ]] || { error "No pending firewall change."; return 1; }
    systemctl stop lemper-firewall-rollback.timer 2>/dev/null || true
    rm -f /etc/lemper/firewall/pending
    touch /etc/lemper/firewall/managed
}
function lemper_nft_rollback_policy() {
    local root=/etc/lemper/firewall temporary
    if [[ "${DRYRUN:-false}" == true ]]; then info "Would restore the previous scoped firewall policy."; return 0; fi
    [[ -f "$root/pending" ]] || { error "No pending firewall change."; return 1; }
    if [[ -s "$root/previous.nft" ]]; then
        temporary=$(mktemp "$root/.rollback.XXXXXXXX") || return 1
        { printf 'add table inet lemper
delete table inet lemper
'; cat "$root/previous.nft"; } > "$temporary"
        if ! nft -c -f "$temporary" || ! lemper_exec nft -f "$temporary"; then rm -f "$temporary"; return 1; fi
        rm -f "$temporary"
    else
        nft list table inet lemper >/dev/null 2>&1 && lemper_exec nft delete table inet lemper
        systemctl disable lemper-nftables.service >/dev/null 2>&1 || true
    fi
    if [[ -f "$root/previous-config.nft" ]]; then mv -T "$root/previous-config.nft" "$root/current.nft"; else rm -f "$root/current.nft"; fi
    if [[ "$(cat "$root/previous-ufw")" == true ]]; then lemper_exec ufw --force enable || return 1; fi
    systemctl stop lemper-firewall-rollback.timer 2>/dev/null || true
    rm -f "$root/pending"
    info "Previous firewall policy restored; unrelated tables retained."
}
function lemper_nft_remove_policy() {
    if [[ "${DRYRUN:-false}" == true ]]; then info "Would remove only inet lemper rules."; return 0; fi
    [[ ! -f /etc/lemper/firewall/pending ]] || { error "Confirm or roll back before removing the firewall."; return 1; }
    [[ -f /etc/lemper/firewall/current.nft ]] || { error "No managed firewall configuration."; return 1; }
    if nft list table inet lemper >/dev/null 2>&1; then lemper_exec nft delete table inet lemper || return 1; fi
    lemper_exec systemctl disable --now lemper-nftables.service
}

# A dedicated mutex lets timed recovery proceed during unrelated long backups,
# while serializing it with normal apply/confirm/rollback operations.
function lemper_nft_execute() {
    local callback="$1" root=/etc/lemper/firewall
    shift
    if [[ "${DRYRUN:-false}" == true ]]; then "$callback" "$@"; return $?; fi
    [[ ! -L "$root" ]] || { error "Refusing a symlink firewall state directory."; return 1; }
    install -d -m0700 "$root" || return 1
    (
        local fd
        umask 077
        exec {fd}>"$root/recovery.lock" || return 1
        flock "$fd" || return 1
        "$callback" "$@"
    )
}
function lemper_nft_apply() { lemper_nft_execute lemper_nft_apply_policy "$@"; }
function lemper_nft_confirm() { lemper_nft_execute lemper_nft_confirm_policy "$@"; }
function lemper_nft_rollback() { lemper_nft_execute lemper_nft_rollback_policy "$@"; }
function lemper_nft_remove() { lemper_nft_execute lemper_nft_remove_policy "$@"; }
