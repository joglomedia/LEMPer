#!/usr/bin/env bash
# Real backups, monitoring and native firewall UAT inside a designated disposable container.
# shellcheck disable=SC2016 # Child shells intentionally expand fixed scripts.
set -euo pipefail
[[ $(id -u) == 0 && -f /run/.containerenv && -f /run/lemper-p2-uat-authorized && $(cat /proc/1/comm) == systemd ]] || exit 2
[[ $(findmnt -no OPTIONS /source) == ro,* ]] || exit 2
for dependency in ip socat nft; do
    command -v "$dependency" >/dev/null || {
        echo "P2 UAT requires $dependency." >&2
        exit 2
    }
done
root=/run/lemper-p2
logs=/var/log/lemper-p2-uat
install -d -m0700 "$root" "$logs"
install -d -m0755 /checkout
cp -a /source/bin /source/lib /source/scripts /source/etc /source/share /checkout/
cp /source/.env.dist /checkout/.env.dist
# shellcheck source=/dev/null
. /checkout/lib/core/loader.sh
lemper_load_module core/deployment
lemper_cli_snapshot /checkout
install -m0600 /source/.env.dist /etc/lemper/lemper.conf
rm -rf "$root/restore"
count=0
check() {
    local name="$1"
    shift
    if "$@" >"$logs/$name.log" 2>&1; then
        count=$((count + 1))
        printf 'PASS %02d %s\n' "$count" "$name"
    else
        printf 'FAIL %s (private log: %s/%s.log)\n' "$name" "$logs" "$name"
        exit 1
    fi
}
check restic-install lemperctl stack install restic --yes
install -d -m0700 /srv/p2-app/uploads /var/vmail/p2.test/user
printf 'application-data\n' >/srv/p2-app/uploads/probe
printf 'mail-message\n' >/var/vmail/p2.test/user/message
check encrypted-data-backup lemperctl data backup /srv/p2-app /var/vmail
check data-integrity lemperctl data check
check staged-restore lemperctl data restore latest --target "$root/restore"
check restored-application cmp /srv/p2-app/uploads/probe "$root/restore/srv/p2-app/uploads/probe"
check restored-mail cmp /var/vmail/p2.test/user/message "$root/restore/var/vmail/p2.test/user/message"
for item in 1 2 3; do
    printf '%s\n' "$item" >/srv/p2-app/uploads/counter
    lemperctl data backup /srv/p2-app /var/vmail >"$logs/backup-$item.log" 2>&1
done
check data-retention lemperctl data prune --keep=2
check data-snapshot-count bash -c 'RESTIC_REPOSITORY=/var/backups/lemper/data RESTIC_PASSWORD_FILE=/etc/lemper/restic.pass restic snapshots --json --tag lemper-data | jq -e '\''length==2'\'''
check data-schedule lemperctl data schedule /srv/p2-app /var/vmail
check scheduled-data-run systemctl start lemper-data-backup.service
check backup-timer systemctl is-enabled --quiet lemper-data-backup.timer
mariadb -e 'CREATE DATABASE IF NOT EXISTS p2db; CREATE TABLE IF NOT EXISTS p2db.probe(id INT);'
for item in 1 2 3; do lemperctl db backup --dbname=p2db --dbfile=/var/backups/lemper/p2-sql >"$logs/sql-$item.log" 2>&1; done
check sql-retention lemperctl db prune --dbname=p2db --dbfile=/var/backups/lemper/p2-sql --keep=2
check sql-count bash -c '[[ $(find /var/backups/lemper/p2-sql -name "p2db_*.sql.gz" | wc -l) == 2 ]]'
check monitoring-install lemperctl stack install monit --yes
check monitoring-config lemperctl monitor check
check monitoring-status lemperctl monitor status
monitor_alert_configuration() {
    local file result=0
    file=$(mktemp "$root/alerts.XXXXXXXX") || return 1
    cp /etc/lemper/monitoring/monitrc "$file" || return 1
    printf 'set mailserver localhost port 25\nset alert p2@monitor.test\n' >>"$file"
    monit -t -c "$file" || result=$?
    rm -f "$file"
    return "$result"
}
check monitoring-alert-configuration monitor_alert_configuration
check monitoring-authentication bash -c '[[ $(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:2813/) == 401 ]]'
check monitoring-loopback bash -c 'ss -lnt | grep -q "127.0.0.1:2813"; ! ss -lnt | grep -q "0.0.0.0:2813"'
# A private veth network tests kernel enforcement rather than just rule rendering.
ip netns add lemper-p2-client
ip link add p2-server type veth peer name p2-client
ip link set p2-client netns lemper-p2-client
ip addr add 198.18.0.1/30 dev p2-server
ip -6 addr add fd42::1/64 dev p2-server
ip link set p2-server up
ip netns exec lemper-p2-client ip addr add 198.18.0.2/30 dev p2-client
ip netns exec lemper-p2-client ip -6 addr add fd42::2/64 dev p2-client
ip netns exec lemper-p2-client ip link set p2-client up
ip netns exec lemper-p2-client ip link set lo up
command -v socat >/dev/null || {
    echo 'Network UAT requires socat.' >&2
    exit 2
}
sleep 2 # Wait for IPv6 duplicate-address detection before binding listeners.
listener_pids=()
for endpoint in TCP4-LISTEN:80,bind=198.18.0.1 TCP4-LISTEN:9099,bind=198.18.0.1 \
    'TCP6-LISTEN:80,bind=[fd42::1]' 'TCP6-LISTEN:9099,bind=[fd42::1]'; do
    socat "$endpoint,reuseaddr,fork" /dev/null >"$logs/listeners.log" 2>&1 &
    listener_pids+=("$!")
done
sshd_pid=""
trap 'kill "${listener_pids[@]}" 2>/dev/null || true; [[ -z "$sshd_pid" ]] || kill "$sshd_pid" 2>/dev/null || true; ip netns delete lemper-p2-client 2>/dev/null || true; ip link delete p2-server 2>/dev/null || true' EXIT
cat >"$root/connect.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
expected="$1"
for host in 198.18.0.1 '[fd42::1]'; do
    family=TCP4
    [[ "$host" == 198.18.0.1 ]] || family=TCP6
    for port in 80 9099; do
        actual=blocked
        if timeout 2 socat -u /dev/null "$family:$host:$port,connect-timeout=1" 2>/dev/null; then actual=allowed; fi
        if [[ "$port" == 80 ]]; then [[ "$actual" == allowed ]]; else [[ "$actual" == "$expected" ]]; fi
    done
done
BASH
sleep 2
check unfiltered-private-network ip netns exec lemper-p2-client bash "$root/connect.sh" allowed
nft add table inet p2_foreign
rm -f "$root/client-key" "$root/client-key.pub" "$root/known_hosts"
ssh-keygen -q -t ed25519 -N '' -f "$root/client-key"
cp "$root/client-key.pub" "$root/authorized_keys"
ssh-keygen -A
printf '[198.18.0.1]:2222 %s\n' "$(cut -d ' ' -f 1,2 /etc/ssh/ssh_host_ed25519_key.pub)" >"$root/known_hosts"
/usr/sbin/sshd -p 2222 -o PidFile="$root/sshd.pid" -o AuthorizedKeysFile="$root/authorized_keys" -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o PermitRootLogin=prohibit-password
sshd_pid=$(cat "$root/sshd.pid")
ssh_check() {
    ip netns exec lemper-p2-client ssh -i "$root/client-key" -p2222 -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$root/known_hosts" root@198.18.0.1 'test "$(id -u)" = 0'
}
check baseline-ssh-login ssh_check
check native-firewall env SSH_CONNECTION='198.18.0.2 4444 198.18.0.1 2222' lemperctl firewall apply
check ssh-after-native-policy ssh_check
check initial-firewall-confirm lemperctl firewall confirm
check ipv4-ipv6-filtering ip netns exec lemper-p2-client bash "$root/connect.sh" blocked
check foreign-table-preserved nft list table inet p2_foreign
# Arm the actual recovery timer and invoke its callback as a timed rollback substitute.
check ssh-recovery-armed env LEMPER_SSH_ALLOWED_PORTS='22,2222,2223' SSH_CONNECTION='198.18.0.2 4444 198.18.0.1 2222' lemperctl firewall apply
check rollback-timer systemctl is-active --quiet lemper-firewall-rollback.timer
check active-ssh-port-preserved bash -c 'nft list table inet lemper | grep -q 2222'
check timer-rollback-callback-during-backup-lock flock /var/lock/lemper-operation.lock systemctl start lemper-firewall-rollback.service
check ssh-after-rollback ssh_check
check restored-policy ip netns exec lemper-p2-client bash "$root/connect.sh" blocked
check foreign-table-after-rollback nft list table inet p2_foreign
check ssh-policy-confirmation env SSH_CONNECTION='198.18.0.2 4444 198.18.0.1 2222' lemperctl firewall apply
check confirm lemperctl firewall confirm
check native-reload systemctl reload lemper-nftables.service
check native-remove lemperctl firewall remove --yes
check unfiltered-after-owned-removal ip netns exec lemper-p2-client bash "$root/connect.sh" allowed
check ufw-install apt-get install -q -y ufw
setup_ufw() {
    ufw default deny incoming && ufw allow 22/tcp && ufw allow 2222/tcp && ufw allow 80/tcp && ufw --force enable
}
check ufw-baseline setup_ufw
reject_implicit_migration() {
    if lemperctl firewall apply; then return 1; fi
    ufw status | grep -q '^Status: active'
}
check ufw-explicit-migration-required reject_implicit_migration
check ufw-migration env SSH_CONNECTION='198.18.0.2 4444 198.18.0.1 2222' lemperctl firewall apply --migrate-from-ufw
check ufw-disabled-after-migration bash -c 'ufw status | grep -q "^Status: inactive"'
check ssh-after-ufw-migration ssh_check
check ufw-migration-rollback lemperctl firewall rollback
check ufw-restored bash -c 'ufw status | grep -q "^Status: active"'
check ssh-after-ufw-rollback ssh_check
ufw disable
nft delete table inet p2_foreign
kill "$(cat "$root/sshd.pid")"
check data-component-removal lemperctl stack remove restic --force --yes
check repository-retained test -f /var/backups/lemper/data/config
check monitoring-removal lemperctl stack remove monit --force --yes
check monitoring-config-retained test -f /etc/lemper/monitoring/monitrc
printf '%s checks passed on %s.\n' "$count" "$(dpkg --print-architecture)"
