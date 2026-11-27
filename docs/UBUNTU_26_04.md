# Ubuntu 26.04 (Resolute) in LEMPer v4

Ubuntu 26.04 uses the same Bash CLI, profile validation and component drivers as
Jammy, Noble and Debian. Distribution detection also works when lsb-release is not
installed; unsupported interim releases and unknown distributions remain rejected.

## Package choices

| Component | Resolute selection | Existing supported systems |
|---|---|---|
| PHP | Maintained Sury archive; fingerprint-pinned archive keyring | Same archive on Jammy, Noble, Bullseye and Bookworm |
| MariaDB | Ubuntu's signed MariaDB 11.8 packages when MYSQL_VERSION=auto | auto resolves to the existing MariaDB 11.4 repository |
| Mail | Postfix and a dedicated Dovecot 2.4 template | Existing Dovecot 2.3 template remains available |
| Nginx | MyGuard's published Resolute suite, subject to its binary architecture check; source installation on ARM64 | Existing MyGuard/source choices |
| Python dependencies | Native Python 3.14 packages, without a deadsnakes PPA | Existing dependency choices |
| Base/Memcached packages | Current GPGME/PCRE2 development and t64 Memcached library names | Existing package names |

Fresh profiles use MYSQL_VERSION="auto". Explicit versions remain explicit:
MYSQL_VERSION="11.4" is rejected on Resolute because that repository is not
published there. Select auto or 11.8 for a fresh Resolute installation. An installed
database from another series or a custom MariaDB repository/mirror requires a
deliberate migration; the installer does not silently change its major series.

Ubuntu's MariaDB 11.8 packages use /var/lib/mariadb for new databases. The
installer lets mariadb-install-db honor package configuration and assign mysql
ownership, and preserves the distribution's service helper. Forced data removal
targets the platform's default directory; custom data directories remain manual.
Database operations use SQL inventory rather than assuming a filesystem path.

LEMPer extracts the signing key from the Sury keyring package, verifies the
primary fingerprint, and scopes PHP sources to
`/usr/share/keyrings/debsuryorg-archive-keyring.gpg`. Existing PHP
PPA/Sury entries migrate to the current distribution suite, preserving source
options, deb-src entries and unrelated repositories. Mixed URI stanzas and
signature bypasses are rejected before source changes. Sources are backed up as
*.lemper-before-php-repository; an APT refresh failure restores previous sources.
An unused global compatibility key introduced by a fresh bootstrap is retired;
pre-existing/shared signing keys remain protected.

New deployments use the maintained archive on all supported systems. The
installed update command shares the installer driver:

    sudo lemperctl update php --php-version=8.5 --yes

That updates PHP on the current OS. It does not upgrade Ubuntu or migrate
database/mail storage between major versions. PHP removal disables its source
entries while retaining shared keyring packages and other repositories.

## Mail and Nginx

The installer chooses a Dovecot template from the installed version. The 2.4
template declares configuration/storage versions, renamed TLS/authentication
settings, named passwd-file/static databases and modern variable expansions.
It retains TLS-only authentication, virtual per-domain Maildir storage, Unix LMTP
and Postfix authentication sockets, literal plus addresses, private account maps
and the existing add/edit/delete/disable commands. Configuration validation,
backups and generation rollback remain in the existing service driver.

For an existing mail server, follow
[Dovecot's migration guidance](https://doc.dovecot.org/2.4.1/installation/upgrade/2.3-to-2.4.html)
and back up mail/storage before an OS or Dovecot major upgrade. LEMPer's config
backup is not a downgrade mechanism for storage written by a newer Dovecot.

MyGuard's Resolute InRelease is published and its signature verifies. The ARM64
index currently supplies no matching nginx binary candidate, so LEMPer retains
its architecture guard. Use NGINX_INSTALLER="source" on ARM64; do not mix MyGuard
configuration/module packages with a distribution Nginx binary. AMD64 package
publication is distinct from a native AMD64 acceptance test.

## Validation

Use the disposable Linux procedures in [DEVELOPER.md](../DEVELOPER.md).
tests/uat/php_repository_acceptance.sh requires a read-only /source mount, systemd,
and /run/lemper-php-repository-uat-authorized. It checks real signed indexes, PHP
8.4/8.5 CLI/FPM, repeat preservation and migration through the installed CLI.
The CI PHP matrix includes Jammy, Noble, Resolute and Debian 12; the mail matrix
adds Resolute and a separate Ubuntu 26.04 job runs the full Bash suite.

Observed native ARM64 checks include 18 PHP repository checks each on Jammy,
Noble, Resolute and Debian 12; all 19 mail checks on Resolute's Dovecot 2.4; and
an actual native MariaDB 11.8 server/query. Resolute's full base-package request also passes
APT dependency resolution. These checks do not claim an in-place Ubuntu upgrade,
a database-major migration or a native AMD64 deployment.

The complete MariaDB installer also passed native security setup and backup-account
provisioning. A repeat preserved protected credentials; a physical backup and its
prepare step completed against the package-selected /var/lib/mariadb directory.

The final Resolute candidate passed all 513 Bats checks: 511 behavior/structure
cases in the final run and two repository syntax/ShellCheck cases separately.
Ubuntu 24.04 passed an earlier full suite of 509 cases and the subsequent focused
database regressions. Both environments were ARM64. Coverage includes missing
optional distribution metadata under Bash nounset, data ownership, scoped cleanup,
dry-run preservation and SQL inventory.

Bashate is installed from the distribution when available. Resolute no longer
packages it, so test setup installs this third-party lint tool in its own Python
virtual environment. All LEMPer-owned orchestration and test drivers remain Bash.
