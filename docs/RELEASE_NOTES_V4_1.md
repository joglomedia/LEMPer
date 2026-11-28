# LEMPer 4.1.0

Hosting providers can now run an authoritative DNS primary with Knot. External DNS is the
default. Sites, mailboxes and certificates continue to work with their existing DNS providers.

## Hosting customer zones

- Use `lemperctl dns plan` to preview records and `lemperctl dns check` to query each
  authoritative server over UDP and TCP. Both commands also work with external providers.
- To host DNS, configure the primary role, listener and transfer peers in the protected profile,
  then run `sudo lemperctl stack install dns`. A hidden primary can publish to multiple
  secondaries with a separate TSIG key for each peer.
- Enroll each customer's zone explicitly. Publication verifies the served records, rejects
  stale edits and keeps a revision for recovery. Configuration backups include zone data
  and transfer keys.

The primary binds one IPv4 address and hosts unsigned zones, including A and AAAA records.
Keep domains with an active parent DS record on their signed authority. Follow the operator
guide to verify both secondaries before changing registrar delegation.
[DNS setup, verification and recovery](https://github.com/joglomedia/LEMPer/blob/release/v4.1.0/docs/DNS.md)

## Upgrading from 4.0.0

Back up the protected LEMPer configuration and service data before upgrading. An existing
profile can omit the new DNS settings. Installing the CLI alone preserves existing authority.

This release also includes the security fixes developed after 4.0.0. On existing hosts, review
administrator access, mailbox sender aliases, database grants, cache clients and backup
permissions before reconciling those services. The remediation guide identifies changes that
require credential rotation or operator action.
[Existing-installation migration guidance](https://github.com/joglomedia/LEMPer/blob/release/v4.1.0/docs/SECURITY_AUDIT_REMEDIATION.md)
