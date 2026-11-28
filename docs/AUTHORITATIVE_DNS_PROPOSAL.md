# Authoritative DNS for LEMPer

**Implementation status.** The unsigned Knot primary, external planning, publication and
secondary verification are implemented. See the [operator guide](DNS.md) for available commands,
tested deployments and current limits. DNSSEC automation and the comparative performance
benchmark remain planned. The design below records the original scope.

Keep externally managed DNS as the default for a single hosting VPS.
Offer **Knot DNS** as an optional core service for operators who want LEMPer to publish their
zones. Ship the CLI and service independently of the web panel. The first milestone is a DNS
plan that works with any provider and a private, two-server pilot that demonstrates publication,
replication and recovery.

## What LEMPer needs

A hosting operator needs authoritative answers for domains they control. A website visitor's
recursive resolver looks up those answers. Only the authoritative role belongs in this component.
The host keeps its current resolver configuration, including any local stub used by applications.

LEMPer already has a reserved `[dns]` profile section. Its mail CLI prints suggested MX, SPF,
DKIM and DMARC records, and its ACME adapter implements Cloudflare and DigitalOcean DNS-01.
Neither existing workflow requires a local nameserver. Creating a site, mailbox or certificate
does not by itself confer authority over a DNS zone. Model zone ownership and delegation
independently, so removing a site cannot delete a domain's mail or verification records.
[Profile](../.env.dist) · [Mail records](MAIL.md#clients-and-dns) · [ACME adapter](../lib/core/acme.sh)

## Server selection

| Option | Fit for LEMPer |
|---|---|
| **Knot DNS** | Best fit for a hosting primary. It is authoritative-only, accepts standard zone files, supports incremental transfers, and includes automatic DNSSEC signing and key management. It can run without a separate database service. The operational cost is managing its local journal and, once signing is enabled, its keys. [Knot DNS](https://www.knot-dns.cz/) · [Knot operations](https://www.knot-dns.cz/docs/latest/html/operation.html) |
| **NSD** | A strong choice for a file-based authority or independent secondary. Its native configuration and zone checkers suit a small deployment. It serves signed zones, but signing them requires separate tooling. Choose it first if serving externally signed or static zones is the whole job. [NLnet Labs NSD manual](https://nsd.docs.nlnetlabs.nl/en/latest/) |
| **PowerDNS Authoritative** | Worth choosing when a provisioning API or an existing SQL-backed DNS platform drives the design. It also supports plain zone files. For LEMPer's first release, Bash plus the local Knot control socket is sufficient. [PowerDNS backends](https://doc.powerdns.com/authoritative/) · [HTTP API](https://doc.powerdns.com/authoritative/http-api/index.html) |
| **BIND 9** | A good fit for operators with an existing BIND estate or requirements such as DNS views. Its authoritative, recursive and policy capabilities span a wider configuration surface than the proposed service needs. [ISC BIND 9](https://www.isc.org/bind/) |

Debian 12 lists installed amd64 package sizes of **3,310 kB for Knot** and **2,324 kB for NSD**.
Both also have arm64 builds. Ubuntu 24.04 publishes both daemons in Universe. These disk figures
exclude dependencies, zone data, journals and running memory. The performance decision depends
on measuring each service alongside PHP-FPM and the database on LEMPer's single-core, sub-1-GiB
`micro` profile. [Debian Knot](https://packages.debian.org/bookworm/knot) · [Debian NSD](https://packages.debian.org/bookworm/nsd) · [Ubuntu Knot](https://launchpad.net/ubuntu/noble/amd64/knot) · [Ubuntu NSD](https://launchpad.net/ubuntu/noble/amd64/nsd) · [Resource profiles](../.env.dist)

## Deployment choices

| Situation | Recommended deployment |
|---|---|
| One VPS, existing DNS provider | Leave delegation at the provider. LEMPer can generate a record plan and check the published result with zero additional resident processes. A web-host outage leaves DNS available for mail, verification and recovery. |
| Operator wants local control with independent public availability | Use a **hidden Knot primary**. Delegate the domain to at least two public secondaries on independent networks. Select a secondary service that accepts transfers from the primary and supports the required TSIG policy. Restrict access to the hidden listener. |
| Operator runs DNS infrastructure | Support a **public primary and off-host secondary**, or a DNS-only LEMPer host on a separate network from the web stack. Publish at least two reachable nameservers in distinct failure domains. Two names or two IPs on one VPS share the same outage. |

Transfers use a full zone transfer (AXFR) for bootstrap and may use incremental transfers (IXFR)
thereafter. NOTIFY prompts a refresh. Authenticate transfers and notifications with per-peer TSIG
keys and restrict source addresses. Monitor lag and the time remaining before the SOA expiry
deadline. A secondary can continue serving during a primary outage only while its copy is valid.
For signed zones, signature expiry is another deadline. [Secondary placement](https://www.rfc-editor.org/rfc/rfc2182.html) · [Knot operations](https://www.knot-dns.cz/docs/latest/html/operation.html)

## Core implementation

- **Lifecycle.** Propose `dns` as the component name and `INSTALL_DNS=false` as the default.
  Register the component in the existing registry and execution contracts. Put Knot lifecycle and
  validation in `lib/services/dns/`, CLI use cases in `lib/runtime/dns/`, and managed templates
  in `etc/`. Wire the existing install, remove and stack entry points. Use signed distribution
  packages and allow a CLI-only host to install just this component. Check the daemon, checker,
  service paths and supported configuration features on each advertised distro/architecture.
  Preserve unmanaged configurations and refuse an occupied listener without interrupting it.
  [Component contract](MODULE_DECOMPOSITION.md#component-contract) · [Registry](../lib/core/registry.sh)
- **Publication.** Proposed verbs are `lemperctl dns plan`, `dns check`, `dns zone validate`
  and `dns zone apply`. The first two also work with external DNS. Start with a complete,
  operator-supplied zone file per enrolled primary zone and a preview of the changes. Compare
  against the last applied revision, validate using the packaged zone checker, then publish atomically
  under the existing operation lock. Check the served SOA serial and expected records before
  reporting local success. Show secondary convergence separately. On rollback, republish the
  previous contents with a newer SOA serial so secondaries accept the correction.
  [Knot zone checker](https://www.knot-dns.cz/docs/latest/html/man_kzonecheck.html) · [Knot zone loading and journals](https://www.knot-dns.cz/docs/latest/html/operation.html)
- **One writer per zone.** For the first release, LEMPer owns the unsigned input file on the
  primary. Select the packaged Knot version's input-only zone-file mode, keep dynamic updates
  disabled and advance serials relative to the *served* serial using DNS serial arithmetic.
  Secondaries take their copy by transfer. A future dynamic-update mode needs a distinct
  ownership and backup contract, especially for short-lived ACME TXT records. [Knot file and journal modes](https://www.knot-dns.cz/docs/latest/html/operation.html#handling-zone-file-journal-changes-serials) · [SOA serial arithmetic](https://www.rfc-editor.org/rfc/rfc1982.html)
- **Network policy.** Bind explicit service addresses. A public authority needs inbound UDP
  **and** TCP 53. A hidden primary limits both to its transfer peers and approved monitoring
  sources. Keep the control socket local and privileged. LEMPer's UFW setup currently opens 53
  unconditionally, CSF lists it among TCP ports, and native nftables has no DNS service rule.
  Make managed inbound rules follow the selected role, preserve outbound resolution, and
  report existing rules of uncertain ownership before migrating them. Include provider firewall
  checks before delegation. [UFW and CSF setup](../lib/services/system/security.sh) · [nftables rules](../lib/services/firewall/nftables.sh)
- **Ownership and recovery.** Protect TSIG secrets and future signing keys from profiles printed
  by the CLI, logs and dry-run output. Back up the managed config, zones and applicable Knot state
  consistently, including signing keys and timing metadata when enabled. Restore on an isolated
  host and compare its answers with the last good revision. Removal should preserve zone data
  and existing services and identify zones that still depend on this authority. [Knot backup and restore](https://www.knot-dns.cz/docs/latest/html/operation.html) · [LEMPer backups](DATA_BACKUP.md)

## Delivery and acceptance

1. **Provider-neutral planning and a private pilot.** Generate a proposed record set from explicit
   zone membership, confirmed web and mail addresses, and existing mail suggestions. Compare
   those specific record sets with the answers at every delegated nameserver over UDP and TCP.
   Preserve multiple TXT values. A complete migration inventory requires a zone export from its
   owner or provider. External mode makes no changes to the provider. Benchmark packaged Knot
   and NSD with the same zones, query mix, CPU and memory
   limits on disposable Linux hosts. Record added dependency disk usage, idle and peak memory
   during reload/transfer, CPU, answer rate, p95 latency and failures at the same offered load.
   Include concurrent web traffic and set the operating budget from those measurements.
2. **Opt-in unsigned authority.** Deliver install, validate, apply, status and remove. Exercise
   an unsigned test zone across a primary and off-host secondary, including an interrupted apply,
   failed validation, concurrent updates, an unauthorized transfer request, host restart, lost
   primary and restore with a newer serial. Verify authoritative answers, absence of recursion,
   and that the host resolver still works. Run the package and firewall checks on supported
   Debian/Ubuntu releases and amd64/arm64 before advertising compatibility.
3. **Delegation and operational readiness.** Start with a disposable subdomain. Before a production
   cutover, inventory the complete existing zone, compare records at every new authority, check
   registrar NS and glue for nameservers inside the delegated zone, and inspect any DS at the
   parent. Check renewal for every wildcard certificate before moving its challenge records.
   An existing provider token only works while its provider controls the challenge name.
   Keep existing authorities serving throughout the delegation cache window. A zone with a live
   parent DS stays on its signed authority until a signed migration is ready. Keep IP reverse
   DNS/PTR with the address provider unless reverse authority
   was explicitly delegated. Verify external reachability, transfer lag, expiry alerts and
   recovery from a primary outage. [Mail and PTR guidance](MAIL.md#clients-and-dns)
4. **DNSSEC and scoped automation.** Offer signing per zone after demonstrating key backup,
   recovery, rollover, signature-expiry alerts and parent DS publication/verification. Consider
   local DNS-01 after proving narrowly scoped TXT updates, simultaneous challenges and cleanup
   that preserves other TXT values. Existing provider-specific renewal remains available for
   externally managed zones. A future panel can consume the core zone permissions and operations
   once the CLI contract is stable. [Knot signing operations](https://www.knot-dns.cz/docs/latest/html/operation.html) · [Current certificate support](FEATURES.md)
