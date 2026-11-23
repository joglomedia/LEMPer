# Installing LEMPer v4

LEMPer configures system packages, accounts and services directly. Use a fresh
Debian or Ubuntu server for full installation. To upgrade an existing server,
follow [maintenance and updates](MAINTENANCE.md).

## Requirements

- Debian 11 (Bullseye) or 12 (Bookworm), or Ubuntu 22.04 (Jammy), 24.04 (Noble)
  or 26.04 (Resolute), on amd64 or arm64. Linux Mint 21–22 retains its Ubuntu-base
  support.
- Root/sudo access, Bash 5+, curl, tar, SHA256 tools and working APT access.
- An SSH public key and the server's hostname, IP address and administrator email.

On ARM64, select `NGINX_INSTALLER="source"` while MyGuard has no compatible
Nginx binary. Resolute uses native MariaDB 11.8 and Dovecot 2.4; see
[Ubuntu 26.04](UBUNTU_26_04.md) for package choices and validation limits.

## Install from a release

The following commands target **v4.0.0** and become available when it is
published. The earlier v3.6.0 release does not contain these bootstrap assets.
Until then, use a reviewed v4 checkout as described below.

For CLI-only installation:

```bash
curl -fsSL https://github.com/joglomedia/LEMPer/releases/download/v4.0.0/get-lemper -o get-lemper && sudo bash get-lemper --version 4.0.0
```

The bootstrap verifies the versioned archive's SHA256, installs `lemperctl` and
its compatibility alias `lemper-cli`, and preserves existing configuration and
services. The release also supplies `get-lemper.sha256` for the bootstrap itself.
CLI-only installation does not install the stack.

For a full installation, first prepare a private profile:

```bash
curl -fsSL https://raw.githubusercontent.com/joglomedia/LEMPer/v4.0.0/.env.dist -o lemper.env
chmod 0600 lemper.env
${EDITOR:-vi} lemper.env
```

Set `SERVER_HOSTNAME`, `SERVER_IP`, `LEMPER_ADMIN_EMAIL` and `RSA_PUB_KEY`.
Choose PHP versions and optional services using the published
[configuration template](../.env.dist). Never commit a profile containing secrets.

Unattended installation defaults to key-only SSH. Generate an ed25519 key on your
local computer and put its public key in `RSA_PUB_KEY`; missing or invalid keys
are rejected before host changes. Explicit `SSH_PASSWORDLESS=false` supports
a staged migration. Previous SSH firewall ports remain allowed until you verify
a new login and deliberately retire them. See [firewall recovery](FIREWALL.md).

Install the minimal profile:

```bash
curl -fsSL https://github.com/joglomedia/LEMPer/releases/download/v4.0.0/get-lemper -o get-lemper && sudo bash get-lemper --version 4.0.0 --install --config ./lemper.env --minimal --yes
```

Add `--dry-run` to validate and inspect the plan before installation.
`--yes` skips confirmation; it does not bypass validation.

`--minimal` installs Nginx, PHP, MariaDB, Certbot, Fail2ban and CLI tools. It
disables optional databases/caches, FTP, mail, Bun, ImageMagick, CrowdSec,
ModSecurity and web panels. Optional Nginx source modules are disabled and the
distribution PCRE library is used. SSH/firewall policy still follows the profile.
Omit `--minimal` to install the services selected in that file.

## Install from a checkout

Once v4.0.0 is published, install its tagged checkout:

```bash
git clone https://github.com/joglomedia/LEMPer.git
cd LEMPer
git checkout v4.0.0
cp .env.dist .env
chmod 0600 .env
${EDITOR:-vi} .env
sudo bash install.sh --config .env --minimal --yes
```

For the unpublished candidate, use your existing reviewed local
`release/v4.0.0` checkout, then follow the profile and installation steps above.
The candidate branch must be available in your clone; the commands do not
assume it has been published remotely. Review the checkout before running its
installer. Local development and disposable installation tests are documented in
[DEVELOPER.md](../DEVELOPER.md).

After CLI installation, the same lifecycle is available through:

```bash
sudo lemperctl stack install --all --config ./lemper.env --minimal --yes
sudo lemperctl stack install php --php-version 8.5
sudo lemperctl stack status nginx
```

`install.sh`, `remove.sh`, `update.sh` and `lemper.sh` are compatibility entry
points. Legacy `lemper.sh install --with-...` flags remain supported; profiles
are the preferred v4 interface.

## Release selection and configuration

`get-lemper --version VERSION` installs code under `/opt/lemper/VERSION` and
activates it through `/opt/lemper/current`. Configuration remains under
`/etc/lemper`. Selecting an older code release does not restore packages,
databases or service configuration.

Use [CLI management](CLI.md) for site/service commands,
[application deployment](APPLICATIONS.md) for skeleton prerequisites, and
[maintenance](MAINTENANCE.md) for backups, upgrades and removal. Release artifact
building and publication are covered in [release preparation](RELEASE_V4.md).
