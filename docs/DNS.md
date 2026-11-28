# Authoritative DNS

LEMPer can plan records for an external provider or operate a Knot primary for enrolled customer
zones. DNS is off by default and skipped by minimal installations. A DNS-only host can use the
CLI bootstrap and install this single component. The site, mail and panel lifecycles are independent.

## Keep an existing provider

Generate a proposed apex A record, optionally with the existing LEMPer mail service's suggestions.
Review the customer's current MX, TXT and verification records before making provider changes.

```bash
sudo lemperctl dns plan bakery.example --ipv4=192.0.2.10
sudo lemperctl dns plan bakery.example --ipv4=192.0.2.10 --mail
sudo lemperctl dns check bakery.example --ipv4=192.0.2.10
```

Planning an address requires only the CLI. Verification uses `dig` from `dnsutils`. Without server
arguments it looks up the NS set through the host's resolver, then queries every listed server
directly over UDP and TCP. Supply servers explicitly when testing before delegation. The check
requires authoritative answers and matching SOA serials. `--file=ZONEFILE` additionally compares
the TTL and published values of each authoritative record set in an unsigned master file. This
checks expected data. Obtain a complete export from the old provider to discover additional
records. Child-zone referrals and their glue are outside the record-set comparison.

## Configure a hosting primary

In the installed protected LEMPer profile, select the listener and role. The default `local` role
binds to `127.0.0.1` for a private pilot. For a provider's hidden primary, use values like these.
The addresses in this guide are documentation examples.

```ini
INSTALL_DNS=true
DNS_ROLE=hidden
DNS_LISTEN_IPV4=192.0.2.10
DNS_TRANSFER_PEERS="198.51.100.11 203.0.113.12"
```

For each peer, agree a distinct HMAC-SHA256 key with its operator over a protected channel. Put
its base64-encoded 32-byte secret on one line in `/etc/lemper/dns-keys/ADDRESS.key`, owned by root
with mode `0600`. Use a root-owned `0700` directory. To **create a new key** for the first peer
in a root shell, use a no-clobber redirect. An existing key must be coordinated with the secondary
before rotation.

```bash
install -d -m 0700 /etc/lemper/dns-keys
(umask 077; set -C; openssl rand -base64 32 > /etc/lemper/dns-keys/198.51.100.11.key)
```

The TSIG name is `peer-198-51-100-11` for that address. On each secondary, configure the zone
as a secondary of `192.0.2.10`, sign transfer requests with its assigned key, and accept NOTIFY
from the primary authenticated with that key. For an existing Knot secondary the corresponding
configuration sections look like this. Substitute the shared key through protected configuration.

```yaml
key:
  - id: peer-198-51-100-11
    algorithm: hmac-sha256
    secret: "<base64 secret from the protected key file>"
remote:
  - id: hosting-primary
    address: 192.0.2.10
    key: peer-198-51-100-11
acl:
  - id: primary-notify
    address: 192.0.2.10
    key: peer-198-51-100-11
    action: notify
zone:
  - domain: bakery.example
    master: hosting-primary
    acl: primary-notify
```

```bash
sudo lemperctl stack install dns
sudo lemperctl stack status dns
```

The installer uses distro packages and the distro Knot unit with a LEMPer-owned drop-in. It
preserves an existing unmanaged Knot installation. It binds one explicit IPv4 address, serves
A and AAAA records, and leaves the host resolver alone. Set `DNS_ROLE=public` to accept ordinary
queries from the Internet. Transfers still require a configured secondary address and its key.
The hidden role also applies a Knot query ACL to the primary's own address and configured peers.

Allow inbound **UDP and TCP 53** on the chosen address in both the host and provider firewalls.
Restrict a hidden primary to its peers. The full-stack UFW setup and native nftables renderer
use the DNS role in the profile. A component-only install leaves firewall activation to the
operator. Review legacy UFW rules such as an existing broad `allow 53` and any CSF, APF or
provider policies when changing roles. Delegate only to independently reachable public servers.
Check registrar glue for in-zone nameservers. If the parent publishes a DS record, keep the
signed zone on its existing authority. Delegating it to this unsigned primary while that DS
record is live will cause validating resolvers to reject its answers.

## Enroll and publish a customer zone

Enrollment records an operator-attested hosting account ID. Verify the customer's control of the
domain before enrollment. The CLI is an administrator interface. Enrollment neither creates a
Linux user nor changes registrar delegation. A repeat enrollment for a different owner fails.

Use a complete unsigned master file. The parser accepts normal zone-file syntax and runs with
a private filesystem root containing only the input, so external includes must first be flattened.
Here is a new example domain. For production use the customer's existing records and timers.

```dns
$TTL 300
@   IN SOA ns1.hosting.example. hostmaster.hosting.example. ( 1 3600 600 1209600 300 )
@   IN NS  ns1.hosting.example.
@   IN NS  ns2.hosting.example.
@   IN A   192.0.2.10
www IN CNAME bakery.example.
```

```bash
sudo lemperctl dns zone enroll bakery.example bakery
sudo lemperctl dns zone validate bakery.example /root/bakery.zone
sudo lemperctl dns plan bakery.example /root/bakery.zone
sudo lemperctl dns zone apply bakery.example /root/bakery.zone --base=new
sudo lemperctl dns zone status bakery.example
sudo lemperctl dns check bakery.example ns1.hosting.example ns2.hosting.example --file=/root/bakery.zone
```

On subsequent edits, capture the `committed` digest from `zone status` when starting the edit.
Increase the SOA serial, review the diff, then pass that digest as `--base=REVISION`. LEMPer
checks the candidate with the distro BIND compiler and Knot checker, holds the shared operation
lock, retains the immutable revision, and verifies the served primary serial, record sets and
TTLs over UDP and TCP. Reapplying identical
content is safe. Secondary convergence is asynchronous. Complete the explicit secondary check
before switching a customer's delegation.

## Recovery, retirement and scope

- Run `lemperctl dns zone resume DOMAIN` after an interrupted publish to retry its retained
  revision. `zone rollback DOMAIN` republishes the prior contents with a newer serial. With a
  pending edit, rollback uses the last confirmed contents. It also requires a responding primary
  or recovery of its service. Cached answers follow their TTL.
- After moving delegation and allowing caches to expire, use `dns zone retire DOMAIN
  --base=REVISION --yes` to stop serving that zone on the primary. Remove the zone at each
  secondary as well. A secondary can keep answering from its copy until the SOA expiry timer
  runs out. Ownership and revisions remain available on the primary.
  `stack remove dns --yes` stops the whole primary and retains zone and key data.
- Configuration backups include the managed DNS configuration, key inputs and revisions. Store
  these archives privately. For host recovery, install the component on a clean, isolated primary
  to provision the distro account and unit drop-in. Stop it, restore the configuration while
  publication is quiescent, reconcile the component, and check each
  zone against secondary serials before reconnecting transfers. An older backup can require a
  higher SOA serial. The unsigned input files can seed a fresh Knot journal.
- This release manages unsigned primary zones. Public delegation, registrar DS changes, automatic
  signing and local ACME DNS-01 updates are separate operations. The existing provider-backed
  ACME workflow remains available for provider-hosted challenge records. See the
  [DNS proposal](AUTHORITATIVE_DNS_PROPOSAL.md), [mail guide](MAIL.md) and [firewall guide](FIREWALL.md).

## Verification

The ARM64 pilot exercised the installed CLI on Debian 11/12 and Ubuntu 22.04/24.04/26.04.
Debian 11 used its signed archived security repository. A private Debian 12 primary and two
secondaries exercised TSIG transfers, interrupted publication and resume, stale edits,
rollback, primary outage and retirement. A separate Ubuntu 24.04 instance served records
restored from the Debian primary's configuration backup. These checks used private networks.
Public delegation, native amd64 execution and performance under production load still need
deployment-specific validation.

The [GitHub Actions DNS job](../.github/workflows/main.yml) runs the three-server acceptance test
on Debian 12 and Ubuntu 24.04 using amd64 runners. To reproduce the Ubuntu job on Linux with
Podman, run the following from the checkout. The script creates and removes its own containers
and bridge network. It publishes no host ports.

```bash
sudo podman build --build-arg BASE_IMAGE=docker.io/library/ubuntu:24.04 \
  -f tests/uat/Containerfile -t localhost/lemper-dns-uat tests/uat
sudo bash tests/uat/dns_cluster.sh localhost/lemper-dns-uat
```

For an existing disposable primary and two secondaries, configure both secondaries for the
fixture zone `lemper-dns-uat.example`. Run the
[acceptance script](../tests/uat/dns_acceptance.sh) on the disposable primary with
`--disposable PRIMARY_IPV4 SECONDARY1_IPV4 SECONDARY2_IPV4`. It stops and restarts the primary.
