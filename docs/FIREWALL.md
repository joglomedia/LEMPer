# Native nftables firewall

`FW_CONFIGURATOR=nftables` selects the native backend in server-security setup.
UFW remains the default. The native component also has install/remove/update and
service control through `lemperctl stack ... nftables`.

```bash
sudo lemperctl stack install nftables --yes
sudo lemperctl firewall status
sudo lemperctl firewall check
sudo lemperctl firewall apply --dry-run
```

The driver owns only `table inet lemper`. An atomic transaction replaces that
table without `flush ruleset`, preserving unrelated firewall/NAT tables. It refuses
an existing unmarked table or configuration. The input chain denies unsolicited
traffic, accepts loopback and established/related connections, preserves IPv4/IPv6
ICMP, and opens configured SSH plus existing web/admin ports. Mail, remote MySQL,
FTP passive ranges and HTTP/3 UDP follow their existing configuration flags.
Outbound and forwarding policies owned by other software are retained.

Rules persist at `/etc/lemper/firewall/current.nft`; `lemper-nftables.service`
loads them at boot and validates through the native nft CLI. Other security layers
can still reject traffic allowed by this table. Changing a firewall does not
change authentication or service listener configuration.

## SSH recovery and confirmation

```bash
sudo lemperctl firewall apply
# From a working new SSH connection, before the two-minute deadline:
sudo lemperctl firewall confirm
# Or restore the previous policy:
sudo lemperctl firewall rollback
```

A change made in an SSH session retains the active SSH port and any transition
ports supplied by server setup. The driver arms a transient two-minute systemd
rollback timer before changing rules. Its root-owned recovery runner does not
load private configuration or require a bootstrapped CLI; a dedicated firewall
mutex lets recovery proceed while unrelated backup operations hold the shared lock. Confirm from a verified new login; leaving
it unconfirmed restores the previous scoped table, persistence configuration and
UFW state. Local-console changes confirm automatically. The shared operation lock
prevents a second pending change from replacing the recovery snapshot.

## UFW migration

```bash
sudo lemperctl firewall apply --migrate-from-ufw
sudo lemperctl firewall confirm
```

An active UFW configuration requires explicit migration. Native rules are staged
and validated first, then installed before UFW is disabled. Rollback restores
UFW's previous enabled state. Existing CSF/APF installations require an explicit
separate migration; the driver preserves them and refuses automatic replacement.
Do not run parallel firewall administrators against a live SSH transition.

```bash
sudo lemperctl firewall remove --yes
```

Removal deletes only the managed table and disables its unit, retaining configuration
for review. It may leave incoming traffic governed only by other firewall layers;
use an intentional replacement policy. Container UAT verified allowed/blocked
IPv4 and IPv6 connections, actual SSH key authentication, recovery callbacks,
UFW migration/rollback and retention of an unrelated table. Production networking,
provider firewalls and other distro/architecture combinations need their own tests.
