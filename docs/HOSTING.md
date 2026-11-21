# Hosting plans and filesystem quotas

`lemperctl hosting` implements disk and inode quotas for LEMPer-managed Linux
hosting accounts, addressing [issue #39](https://github.com/joglomedia/LEMPer/issues/39).
Plans are administrator-owned data. They assign limits to the account UID on one
quota-ready ext4 filesystem, normally `/home`. Linux enforces the hard limits on
all files owned by that UID on the filesystem, including writes from PHP-FPM,
SSH, and FTP. Inode limits also prevent exhaustion by many small files.

## Prepare the filesystem

Install the distribution's quota tools:

```bash
sudo lemperctl stack install quota
sudo lemperctl hosting check
```

`INSTALL_QUOTA=false` is the default; setting it to true in an installation
profile installs tools only. `HOSTING_QUOTA_MOUNT="/home"` selects the exact,
canonical mount point. A subdirectory of a mount is not a quota target.
An administrator must enable ext4 user quotas and verify persistence after reboot
using the distribution/provider's filesystem maintenance procedure. Back up the
filesystem and plan downtime where required before changing its features or
mount configuration. LEMPer does not edit fstab, remount `/`, run quotacheck, turn
quotas on/off globally, or install a replacement kernel.

The capability check requires an ext4 mount with a UUID, installed quota tools,
and active user quotas. Overlay filesystems, unsupported backends, and providers
without kernel quota support fail explicitly. OpenVZ support depends on the
provider; installing quota utilities alone cannot provide missing kernel support.
The root filesystem can be selected explicitly if it is already quota-ready;
a dedicated `/home` volume is preferable for predictable tenant accounting.

## Create a plan and provision an account

```bash
sudo lemperctl hosting plan put starter \
  --disk-soft=1G --disk-hard=2G --files-soft=50000 --files-hard=60000
sudo lemperctl hosting plan list
sudo lemperctl account alice --plan=starter
sudo lemperctl hosting status
```

Sizes use binary KiB: bare numbers and `K` mean KiB, `M` means MiB, `G` means
GiB, and `T` means TiB. Both hard limits must be positive; a soft limit can be zero
to disable the soft threshold. Soft limits use the existing filesystem grace
policy; hard limits apply immediately. Grace deadlines can change when limits
change; the original numeric limits are the rollback contract.

Account provisioning checks the plan and filesystem before creating the account.
The new account stays password-locked until quota assignment succeeds. Failed
provisioning retains the account, its protected credentials and diagnostic state;
it does not delete data as rollback. Review `hosting status`, recover any pending
transaction, then assign a valid plan before explicitly enabling login.
Existing accounts require a LEMPer provisioning record, a non-system UID, and a
home on the selected filesystem. Ordinary `account` without `--plan` retains its
existing behavior and does not enforce hosting limits.

## Upgrade, downgrade and teardown

```bash
sudo lemperctl hosting plan put larger \
  --disk-soft=4G --disk-hard=5G --files-soft=100000 --files-hard=120000
sudo lemperctl hosting assign alice --plan=larger
sudo lemperctl hosting detach alice --yes --dry-run
sudo lemperctl hosting detach alice --yes
sudo lemperctl hosting plan delete starter --yes
```

An assigned plan is immutable: create a new plan and explicitly reassign each
account. Repeating the same assignment is idempotent. Downgrades below current
disk/inode usage are rejected. Reassignment retains the limits captured before
LEMPer first managed that account's quotas. Detach restores those limits, removes
only the assignment record, and keeps the account, files and services. If the
account previously had no limits, detach restores unlimited usage.

Mutations use the shared operation lock. State records under
`/etc/lemper/hosting/` have mode 0600 in mode-0700 directories and are never sourced.
Each assignment records UID, filesystem UUID, original/current limits and a pending
transaction phase before applying quotas. Failed application attempts rollback;
interrupted or failed rollback remains visible and blocks normal reassignment.

```bash
sudo lemperctl hosting recover alice --yes
```

Recovery deliberately restores the original baseline and detaches the plan;
reassign afterward if the account should remain limited. UID reuse, filesystem
identity changes and external quota edits require manual reconciliation rather
than silently overwriting another administrator's changes. Quota tools and the
full LEMPer installation cannot be removed while assignment records remain.
Do not manually delete an account or wipe quota metadata before detaching it.

## Scope

These are disk/inode hosting packages. They do not claim CPU, RAM, bandwidth,
site-count, database-size or virtual-mailbox limits. Shared service-owned data
(e.g. MariaDB files and virtual mailboxes) does not belong to the hosting UID.
PHP temporary/session storage on another filesystem is outside this quota.
Use a capacity policy for those resources; quotas on `/home` alone cannot protect
the rest of the server from every form of disk exhaustion. Group/project quotas,
XFS/Btrfs backends and broader resource plans remain separate enhancements.

Real UAT uses disposable loop-backed ext4 filesystems, not the container's overlay
root. See [DEVELOPER.md](../DEVELOPER.md) for the Podman procedure.
