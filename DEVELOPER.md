# LEMPer Developer Guide

> **Version:** 4.0.0 (release preparation)
> **Last Updated:** 2026-11-23
> **Target Audience:** Contributors, maintainers, and developers working on LEMPer.

---

## 1. Prerequisites

### 1.1 Local Development Environment

| Tool | Minimum Version | Notes |
|---|---|---|
| Bash | 5.0+ | Required for associative arrays, `mapfile`, etc. |
| Git | 2.25+ | For source management |
| ShellCheck | 0.10.0+ | Static analysis — **mandatory before commit** |
| shunit2 | Latest | Unit testing framework |
| bats-core | 1.14.0 | Integration/CLI structural testing |
| **Podman Machine** | 4.0+ | **Recommended for macOS** — see §3.4 for Linux container testing |
| EditorConfig | — | Tracked editor defaults; scoped shfmt enforcement is in CI |

> **macOS developers:** Use Podman Machine to test scripts in a real Linux environment.
> macOS `sed -i` and `grep -P` behave differently from GNU/Linux. Podman eliminates
> this gap (see [§3.4](#34-container-based-testing-with-podman-machine-macos)).

### 1.2 System Requirements (Target)

- Debian 11/12 or Ubuntu 22.04/24.04/26.04 (amd64 or arm64)
- Root/sudo access for installation testing
- At least 2GB RAM, 20GB disk (swap auto-created for low-RAM systems)

---

The shared implementation now lives in lib/core: configuration/schema,
logging/colors, distro/network, validation/security, resources, SSH, accounts,
ACME, option parsing, and CLI dispatch. scripts/utils.sh and the CLI retain
compatibility wrappers. Runtime/service extraction is implemented; see
[MODULE_DECOMPOSITION.md](docs/MODULE_DECOMPOSITION.md) before adding a driver.

Core modules and each component are linted independently to avoid repeatedly
expanding the shared dependency graph through every installer.
Run the existing Bats suite in Linux; new tests exercise unsafe inputs,
legitimate controls, failure handling, provider arguments, and release integrity.

Full-install fixtures must explicitly configure SSH keys or set
SSH_PASSWORDLESS=false when testing unrelated services. Package/service tests
belong in disposable Linux environments. get-lemper --prefix DIRECTORY permits
bootstrap staging in a fixture without changing system paths.

## 2. Project Structure

The installed command is `lemperctl`; `lemper-cli` remains a compatibility alias.
Its implementation is still `bin/lemper-cli.sh`. Use `lemperctl` in current
command examples and retain the existing filename in source and lint references.

See [ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full architecture overview. The key
directories for development:

| Directory | Purpose | Files to Edit |
|---|---|---|
| `bin/` | CLI entry point | `lemper-cli.sh` |
| `lib/` | Thin compatibility CLI plugins/loaders | `lemper-*.sh` |
| `lib/core/` | Shared primitives, registries, locking and exports | `registry.sh`, `execution.sh`, `deployment.sh` |
| `lib/runtime/` | Command normalization and use-case orchestration | `site/`, `stack/`, `components/`, other command modules |
| `lib/services/` | Component lifecycles, rendering and service operations | Component drivers and service helpers |
| `lib/compat/` | Isolated legacy process boundaries | Component/site/updater adapters |
| `scripts/` | Standalone initialization and lifecycle adapters | `install_*.sh`, `remove_*.sh`, `server_*.sh`, `utils.sh` |
| `etc/` | Configuration templates | `*.conf`, `*.ini`, service files |
| `share/` | Static assets | HTML error pages, index, tool configs |
| `tests/` | Unit & integration tests | New in v3.0 |
| `docs/` | Documentation | Architecture, roadmap, audits, and UAT reports |

---

## 3. Development Workflow

### 3.1 Cloning & Setup

```bash
# Fork the repository on GitHub, then:
git clone https://github.com/<your-username>/LEMPer.git
cd LEMPer

# Copy the example config (never commit your .env!)
cp .env.dist .env

# Install shellcheck locally (macOS with Homebrew)
brew install shellcheck

# Install shunit2
curl -sSL -o /usr/local/bin/shunit2 \
    https://raw.githubusercontent.com/kward/shunit2/master/shunit2
chmod +x /usr/local/bin/shunit2
```

### 3.2 Branch Naming Convention

| Type | Format | Example |
|---|---|---|
| Feature | `feat/<descriptive-name>` | `feat/add-crowdsec-integration` |
| Bugfix | `fix/<descriptive-name>` | `fix/fial-typo-in-create-sh` |
| Security | `sec/<descriptive-name>` | `sec/remove-nopasswd-sudo` |
| Refactor | `refactor/<area>` | `refactor/nginx-module-loading` |
| Documentation | `docs/<area>` | `docs/architecture-document` |
| Test | `test/<area>` | `test/add-db-unit-tests` |

### 3.3 Commit Message Convention

Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

Types: `feat`, `fix`, `sec` (security), `refactor`, `docs`, `test`, `chore`, `perf`, `ci`

Example:
```bash
feat(cli): add 'site list' subcommand to list all vhosts

Implement site_list() function in lemper-manage.sh and wire it
through the CLI dispatcher. Fixes #184.
```

### 3.4 Pre-Commit Checklist

Before every commit, run:

```bash
# 1. ShellCheck — fails if any warnings
shellcheck -s bash bin/lemper-cli.sh
shellcheck -s bash lib/lemper-*.sh
shellcheck -s bash scripts/utils.sh
shellcheck -s bash scripts/install_*.sh
shellcheck -s bash scripts/remove_*.sh
shellcheck -s bash scripts/server_*.sh
shellcheck -s bash scripts/nginx/*.sh
shellcheck -s bash scripts/install_crowdsec.sh scripts/remove_crowdsec.sh
shellcheck -s bash lib/core/lemper-stacks.sh

# 2. Shell formatting (bashate-style checks)
# (In v3.0, a .editorconfig will enforce tab-vs-space, line length, etc.)

# 3. Unit tests in a disposable Linux container
bash scripts/test_podman.sh --test

# 4. Verify .env is not tracked
git status --porcelain | grep '.env' && echo "ERROR: .env is tracked!" && exit 1
```

> **Note:** The CI pipeline runs these checks automatically. A failing check blocks the PR.

### 3.4 Container-Based Testing with Podman Machine (macOS)

LEMPer is designed for Linux but many developers work on macOS. Use **Podman Machine**
to validate scripts in a real Ubuntu/Debian environment:

#### 3.4.1 Setup

```bash
# Install Podman (if not already installed)
brew install podman
podman machine init --cpus 4 --memory 4096 --disk-size 64
podman machine start
```

#### 3.4.2 Run Full Validation (ShellCheck + Bats)

```bash
# From the LEMPer project root (checkout mounted read-only):
bash scripts/test_podman.sh           # ShellCheck 0.11.0 + full Bats suite
bash scripts/test_podman.sh --lint    # ShellCheck only
bash scripts/test_podman.sh --test    # Bats only
```

The helper uses `scripts/prepare_tests.sh` for the shared Debian/Ubuntu fixture
packages, SSH host keys and pinned native ShellCheck binary. Primary CI, Debian
CI, release checks and coverage use the same preparation. In a designated
**disposable Linux environment**, equivalent commands are:

```bash
bash scripts/prepare_tests.sh
bash scripts/run_tests.sh
bash scripts/run_tests.sh --coverage /var/tmp/lemper-coverage
```

These commands require root: trusted-directory, sudoers and OpenSSH fixtures
exercise real ownership and configuration checks. `run_tests.sh` provides private
temporary state and a test lock; each unit fixture has its own operation lock.
Preparation installs test dependencies and must run only inside the designated
container/CI runner.

#### 3.4.3 Installation dry-run fixture

Use bash scripts/test_podman.sh --dry-run after inspecting that mode. It copies
the checkout and creates a synthetic configuration in a disposable Linux
container. The mode requests a privileged container; it does not prove a live
installation or make all sourced code harmless outside that container.

#### 3.4.4 Real installation and CLI UAT

The real UAT uses systemd as PID 1 and performs package installation, site
creation, HTTP/TLS requests, SSH key login, backup/restore, and destructive removal inside an
explicitly marked disposable Podman container. The checkout stays read-only.

On ARM64, MyGuard currently advertises the architecture but supplies no Nginx
binary candidate; use the supported source installer for the native UAT. The
source profile builds PAM and cache-purge modules. MyGuard repository behavior
must be reported separately from a successful source-profile run.

~~~bash
podman build -t localhost/lemper-uat:ubuntu24 -f tests/uat/Containerfile tests/uat
podman run -d --name lemper-uat-ubuntu24 --privileged --systemd=always \
  --cgroupns=private --hostname lemper-uat.test --cpus 2 --memory 3g \
  --tmpfs /run --tmpfs /tmp -v "$PWD:/source:ro" localhost/lemper-uat:ubuntu24
podman exec -e LEMPER_UAT_NGINX_INSTALLER=source lemper-uat-ubuntu24 \
  bash /source/tests/uat/prepare.sh
podman exec -w /checkout lemper-uat-ubuntu24 bash scripts/server_cleanup.sh
podman exec -w /checkout lemper-uat-ubuntu24 bash scripts/install_dependencies.sh
podman exec -w /checkout lemper-uat-ubuntu24 bash shunit2/run_test.sh
podman exec lemper-uat-ubuntu24 certbot register --non-interactive \
  --register-unsafely-without-email --agree-tos
podman exec -w /checkout lemper-uat-ubuntu24 bash tests/uat/cli_acceptance.sh
podman stop --time 10 lemper-uat-ubuntu24
~~~

The profile generates a synthetic key and credentials in the container. Certbot
uses the staging directory and package-only installation; the explicit staging
registration uses no real mailbox. Public ACME HTTP/DNS challenges need their
own routable domain/provider setup and are outside this local UAT.

`cli_acceptance.sh` checks real installed services, WordPress/PHP HTTP,
multi-version PHP install/update/control/removal, CORS/cache headers, site state
and TLS, SSH key authentication, configuration backup, and database/webroot purge.
It waits for graceful Nginx reloads, requires a real FastCGI cache hit with CORS
headers, restores a modified synthetic configuration file from backup, and uses
the generated CA for TLS verification.
Per-case logs stay under `/var/log/lemper-uat/cli`.
See [UAT_REPORT.md](docs/UAT_REPORT.md) for recorded results and environment limitations.

The PHP/Laravel policy UAT marks its fully published test configuration with a
generation header. Assertions wait for that generation because old Nginx workers
can finish requests during a graceful reload. The marker is confined to the fixture.

For the v4 release bootstrap, first build the assets into `dist/v4.0.0/`
from the reviewed committed checkout, then run the fresh-container acceptance
script. It installs the archive through `get-lemper` and removes the stack at
the end; use a new explicitly designated container.

~~~bash
bash scripts/build_release.sh 4.0.0 dist/v4.0.0
podman run -d --name lemper-v4-release-uat --privileged --systemd=always \
  --cgroupns=private --hostname lemper-v4-release.test --cpus 2 --memory 3g \
  --tmpfs /run --tmpfs /tmp -v "$PWD:/source:ro" localhost/lemper-uat:ubuntu24
podman exec -e LEMPER_UAT_NGINX_INSTALLER=source lemper-v4-release-uat \
  bash /source/tests/uat/prepare.sh
podman exec lemper-v4-release-uat bash /source/tests/uat/v4_acceptance.sh
podman stop --time 10 lemper-v4-release-uat
~~~

See [RELEASE_V4.md](docs/RELEASE_V4.md) for the final v4 results and artifact
publication steps.

#### Protocol and remote integration acceptance

Use a fresh Ubuntu 26.04 fixture for the HTTP/3 client/source-TLS checks. The
preparation script checks root, systemd, the read-only checkout and the distro
before package changes. It verifies the published curl archive digest and uses
the shared checksummed OpenSSL/Nginx drivers. Pins identify this test fixture.

~~~bash
podman build --build-arg BASE_IMAGE=ubuntu:26.04 \
  -f tests/uat/Containerfile -t localhost/lemper-protocols:resolute tests/uat
podman run -d --name lemper-protocols-uat --privileged --systemd=always \
  --cgroupns=private --cpus 2 --memory 3g --tmpfs /run --tmpfs /tmp \
  -v "$PWD:/source:ro" localhost/lemper-protocols:resolute
podman exec lemper-protocols-uat bash /source/tests/uat/protocol_prepare.sh
podman exec lemper-protocols-uat bash /source/tests/uat/protocol_acceptance.sh
podman stop --time 10 lemper-protocols-uat
~~~

The acceptance script forces HTTP/3, checks TLS 1.3 and Alt-Svc, verifies the
disabled early-data default with cached-session requests, and rejects an untrusted
certificate and mismatched hostname. The upstream curl client enables its
experimental session-export feature for this fixture; LEMPer early-data defaults
stay unchanged.

Check the client's `curl --version` feature list: distribution and standard
container builds can omit HTTP/3 even when their version is recent.

`tests/uat/remote_integrations_acceptance.sh` uses the same marked systemd client
fixture after preparing a separate key-only SSH/SFTP backend and strict known-host
data. It checks encrypted data backup, scheduled execution, staged restore,
retention and host-key rejection. `--restic-only` omits the alert fixture;
`LEMPER_UAT_RESTIC_REPOSITORY` and `LEMPER_UAT_SSH_TARGET` select its test endpoint.
The full mode also needs a private port-25 SMTP sink named `lemper-uat-backup`
and tests real Monit failure/recovery notifications. The sink script captures
messages privately and does not forward them.

For public-server tests, inventory existing services, use separately named/labelled
containers and private networks, cap resources, and bind only unused test ports.
PAM-enabled SSH test containers may need `--cap-add AUDIT_WRITE`. Launching their
daemon through a named, collected `systemd-run` operation avoids inheriting the
operator's already-set audit login ID; keep PAM enabled and remove only the test
unit/container. Private-address
VPSes require provider port mappings for Internet-facing QUIC/ACME; an existing
verified SSH connection can tunnel SFTP without changing service/firewall routing.
See [PRODUCTION_UAT.md](docs/PRODUCTION_UAT.md) for scope and evidence.

#### Public DNS-01 and protocol fixtures

The public drivers require explicit disposable-container markers, root inside
the container and a read-only `/source` mount. Use a reserved `uat-*` subdomain;
keep tokens outside source/build contexts in mode-0600 files. Run the legacy
upgrade/install/remove tests on a disposable clone instead of the production host.
The [public UAT report](docs/PRODUCTION_UAT.md#public-follow-through-2026-11-25)
records tested versions, resource limits and cleanup.

Build `tests/uat/PublicAcme.Containerfile` for the VPS architecture. The image
provides systemd, Python/venv, cron and Nginx; LEMPer's actual Certbot component
installer supplies Certbot and its DNS plugin during acceptance. Run it rootless
with its own hostname, private cgroup namespace, 0.5 CPU, 512 MiB RAM, no extra
swap and a 256-process limit. Mount public source at `/source:ro` and the protected
raw Cloudflare token file at `/run/lemper-cloudflare-token:ro`.

Older Podman installations can lack delegated user CPU/memory controllers.
Use a dedicated, collected systemd unit with `User` set to the unprivileged
operator, `Delegate=yes`, `CPUQuota=50%`, `MemoryMax=512M`, `TasksMax=256` and
`XDG_RUNTIME_DIR=/run/user/<operator-uid>`. Run Podman with
`--cgroup-manager=cgroupfs` inside that unit. This delegates only the test unit;
avoid changing an existing user manager or service. Older builds use
`--network=private` for image builds and `--network=slirp4netns` for containers.

Inside the designated ACME container, set the marker and run:

~~~bash
touch /run/lemper-public-uat-authorized
LEMPER_UAT_ACME_DOMAIN=uat-v4.example.com \
LEMPER_UAT_ACME_EMAIL=operator@example.com \
  bash /source/tests/uat/public_acme_acceptance.sh
~~~

The driver exercises real staging and production DNS-01 issuance, base/wildcard
SANs, credential modes, the installed renewal hook, verified HTTPS and repeated
installation. It disables scheduled renewal jitter for UAT only. Raw logs and
credentials remain under the container's private `/var/log/lemper-public-uat`.

For Internet-facing protocols, copy only the test certificate/key into a protected
fixture directory containing an empty `authorized` marker. Mount that directory
at `/fixture:ro` and public code at `/source:ro` in the official Nginx container.
Run `public_protocol_server.sh` as its entry point, set `LEMPER_UAT_ACME_DOMAIN`
and `LEMPER_UAT_PUBLIC_PORT`, and publish the same unused TCP/UDP high port to
internal port 443. Cap this separate endpoint at 0.25 CPU and 128 MiB RAM.
The script uses LEMPer's SSL template and HTTP/3 driver, then adjusts this
fixture's Alt-Svc to the external port. Public assets are copied to the served
directory so the worker does not require access to the private source parent.

Use a separate Ubuntu 26.04 client container with read-only `/source`, create
`/run/lemper-public-client-authorized`, and run
`public_protocol_client_prepare.sh`, followed by `public_protocol_acceptance.sh`
with the same domain/port. The checksum-verified curl build supports HTTP/2 and
HTTP/3 and persists under `/var/tmp`; `/run` tmpfs contents disappear on stop.
Its session export is experimental and confined to UAT.

Inventory both host/provider firewall rules before publishing a port. Temporary
host rules should admit only the test client's address. After testing, revoke the
disposable certificate, remove only test-created DNS records/rules/containers and
private staging, then compare production service state, HTTP and rule/DNS baselines.
Close the temporary provider port allowance through the operator's normal access.

#### Database, diagnostics and repository-key acceptance

The scoped P1 suite installs real MariaDB/PHP packages, activates a CLI snapshot,
and verifies SQL backup/restore, protected credentials, cron execution and repeat
scheduling, diagnostic redaction/JSON, and signing-key migration. Use a fresh
designated systemd container and copy the test before running it:

```bash
podman run -d --name lemper-p1-ubuntu24 --privileged --systemd=always \
  --cgroupns=private --hostname lemper-p1.test --cpus 2 --memory 3g \
  --tmpfs /run --tmpfs /tmp -v "$PWD:/source:ro" localhost/lemper-uat:ubuntu24
podman exec lemper-p1-ubuntu24 bash -c \
  'apt-get update -qq && apt-get install -y -qq gnupg && touch /run/lemper-p1-uat-authorized && cp /source/tests/uat/p1_acceptance.sh /run/p1-uat.sh && bash /run/p1-uat.sh'
podman stop --time 10 lemper-p1-ubuntu24
```

Build the base image using the existing `tests/uat/Containerfile` instructions.
Logs and synthetic passwords remain inside the container. Signature, fingerprint
and checksum failures must remain failures; report upstream repository outages
separately from successful local tests. See [database management](docs/DATABASE.md).

#### P2 backup, monitoring and firewall acceptance

Use a fresh designated systemd container. The suite validates real encrypted data
backup/restore, SQL/data retention, timers, Monit authentication, IPv4/IPv6 packet
filtering, SSH key login, independent recovery and explicit UFW migration/rollback.
It creates a private veth network and changes firewall rules only in that container.

```bash
podman run -d --name lemper-p2-ubuntu24 --privileged --systemd=always \
  --cgroupns=private --hostname lemper-p2.test --cpus 2 --memory 3g \
  --tmpfs /run --tmpfs /tmp -v "$PWD:/source:ro" localhost/lemper-uat:ubuntu24
podman exec lemper-p2-ubuntu24 bash -c \
  'apt-get update -qq && apt-get install -y -qq gnupg mariadb-server nftables && systemctl start mariadb && touch /run/lemper-p2-uat-authorized && cp /source/tests/uat/p2_acceptance.sh /run/p2-uat.sh && bash /run/p2-uat.sh'
podman stop --time 10 lemper-p2-ubuntu24
```

The test copies source to an internal checkout and keeps synthetic logs/credentials
inside the container. Remote Restic destinations and external SMTP alert delivery
require separate destination/provider tests. See [data backups](docs/DATA_BACKUP.md),
[firewall](docs/FIREWALL.md) and [monitoring](docs/MONITORING.md).

#### Mail hosting acceptance tests

The mail acceptance suite installs only the mail component in a designated
systemd container. It exercises SMTP/IMAP TLS, multi-domain delivery and DKIM,
account/alias changes, session revocation, package updates, backups, and removal
that retains mail. The CI mailer matrix runs Ubuntu 22.04/24.04/26.04 and Debian 12.

```bash
podman build --build-arg BASE_IMAGE=ubuntu:24.04 -t lemper-mail-uat \
  -f tests/uat/Containerfile tests/uat
podman run -d --name lemper-mail-uat --privileged --systemd=always \
  --cgroupns=private --hostname mail.lemper-uat.test --cpus 2 --memory 2g \
  --tmpfs /run --tmpfs /tmp -v "$PWD:/source:ro" lemper-mail-uat
podman exec lemper-mail-uat bash -c \
  'touch /run/lemper-mail-uat-authorized; cp /source/tests/uat/mail_acceptance.sh /run/mail-uat.sh; bash /run/mail-uat.sh'
podman stop --time 10 lemper-mail-uat
```

Use a fresh designated container and a read-only project mount. Copy the UAT
script inside it before execution so ongoing checkout edits cannot change a
running test. Per-case logs and synthetic secrets stay inside the container;
see [the mail guide](docs/MAIL.md) for requirements and validation limits.

#### PHP defaults and Laravel routing acceptance

The `runtime-routing-uat` CI job prepares a disposable Ubuntu 24.04 systemd
container with PHP 8.3/8.4, Nginx, and Laravel 13. It runs
`tests/uat/runtime_routing_acceptance.sh` against installed CLI code. The checks
cover encrypted-profile/default changes, independent FPM runtimes, root/mounted
Laravel requests, static files, redirects, authentication, and guarded removal.

For local UAT, use the same Podman/container commands and package preparation
from `.github/workflows/main.yml`. The PHP PPA is the existing supported
Ondřej source used by LEMPer. Copy the acceptance script into `/run` before
execution and mount only the project, read-only. Mark the designated disposable
container with `/run/lemper-runtime-uat-authorized`; the script refuses an
unmarked/non-systemd environment. Logs stay in `/var/log/lemper-runtime-uat`.
See [PHP_RUNTIME_LARAVEL.md](docs/PHP_RUNTIME_LARAVEL.md) for the contracts and
recorded validation limits.

#### 3.4.5 macOS vs Linux Portability Gotchas

| Construct | macOS (BSD) | Linux (GNU) | Portable Alternative |
|---|---|---|---|
| `sed -i 's/x/y/g' file` | Requires `sed -i '' '...'` | `sed -i 's/x/y/g' file` | Wrap in `sed_inplace()` helper |
| `grep -P 'pattern'` | Not supported | Supported | Use `grep -E` (ERE) or `perl` |
| `date +%N` | Nanoseconds always 0 | Real nanoseconds | Use `gdate` from coreutils on macOS |
| `stat -f` | BSD `stat -f` | GNU `stat -c` | Check `uname` or use `stat --format=` |

Host-side edits use the portable sed_inplace helper. GNU sed remains appropriate
inside Debian/Ubuntu CI and container commands. Validate runtime behavior on
Linux rather than relying on macOS command compatibility.


---

## 4. Coding Standards

### 4.1 ShellCheck Compliance

All Bash scripts must pass `shellcheck -s bash` with **zero warnings**. The most common
ShellCheck directives used in the codebase:

```bash
# shellcheck disable=SC1091   # Sourcing external file
# shellcheck disable=SC2086   # Unquoted variables (intended for word-splitting)
# shellcheck disable=SC2046   # $(...) in command context
# shellcheck disable=SC2206   # Array assignment from word-splitting
```

Use these sparingly and only when you understand the rule being disabled.

### 4.2 Code Style

| Rule | Example |
|---|---|
| **Indentation** | 4 spaces (no tabs in new code) |
| **Variable naming** | `UPPER_SNAKE_CASE` for globals, `lowerCamelCase` for locals |
| **Function naming** | `verb_noun` pattern (e.g., `create_vhost`, `validate_fqdn`) |
| **Strings** | Double quotes preferred; use `"${VAR}"` not `${VAR}` |
| **`local` variables** | Always use `local` inside functions |
| **Line length** | Max 120 characters |
| **Shebang** | `#!/usr/bin/env bash` |

### 4.3 Error Handling

Use the `run` helper function for all system-modifying commands:

```bash
# ✅ Correct
run systemctl restart nginx
run mkdir -p "/etc/lemper/ssl/${DOMAIN}"

# ❌ Incorrect (bypasses DRYRUN and error checking)
systemctl restart nginx
mkdir -p "/etc/lemper/ssl/${DOMAIN}"
```

The `run` function (defined in `scripts/utils.sh`) respects `DRYRUN` mode and exits on
failure.

### 4.4 Guard Clauses

Every installation script must include the standard guard:

```bash
# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    . "${BASE_DIR}/utils.sh"
    requires_root "$@"
    preflight_system_check
fi
```

Every CLI plugin must include the direct-access guard:

```bash
if [[ "$(type -t requires_root)" != "function" ]]; then
    echo "Direct access to this script is not permitted."
    exit 1
fi
```

### 4.5 Sourced vs Executed

- Scripts in `scripts/` are **sourced** by `install.sh` / `lemper.sh` — they share the
  parent process scope and must not call `exit` (use `return` instead).
- Scripts in `lib/` are **copied** to `/etc/lemper/cli-plugins/` and **sourced** by
  `bin/lemper-cli.sh` — they also share scope and must not call `exit` at top level
  (only inside subcommand functions).
- `install.sh`, `remove.sh`, and `lemper.sh` are **executed directly** and may call `exit`.

---

## 5. Testing

### 5.1 Test Framework

| Framework | Purpose | Tests |
|---|---|---|
| **bats-core** | Structural, syntax, and mock-based unit tests | See current Bats suite (primary) |
| **shunit2** | Legacy unit tests (still present) | `shunit2/run_test.sh` |

### 5.2 Running Tests

```bash
# Full test suite (bats)
bats tests/ tests/unit/

# ShellCheck on all scripts (must pass with exit 0)
shellcheck -s bash -x \
    install.sh remove.sh update.sh lemper.sh \
    bin/lemper-cli.sh \
    lib/lemper-*.sh lib/core/lemper-stacks.sh \
    scripts/install_*.sh scripts/remove_*.sh scripts/utils.sh \
    scripts/server_*.sh scripts/nginx/*.sh \
    tests/*.bats

# Or in one line:
find . -name '*.sh' -not -path './.git/*' -not -path './etc/*' \
    | xargs shellcheck -s bash -x
```

### 5.3 Writing Unit Tests

Unit tests live in `tests/unit/` and use bats-core. Helpers under test run in a
child shell so the Bats `run` helper stays available, and external commands are
replaced with PATH-shadowing mocks:

```bash
# tests/unit/validators.bats
#!/usr/bin/env bats

load env_helper

setup() {
    unit_setup
}

@test "validate_fqdn accepts valid domains" {
    run env BASE_DIR="${BASE_DIR}" bash -c \
        'safe_parse_dotenv() { :; }; . "${REAL_BASE_DIR}/scripts/utils.sh"; validate_fqdn "$1"' \
        _ example.com
    [ "${output}" = "true" ]
}
```

For command-level tests, create a temporary mock directory and prepend it to
`PATH` — see `tests/unit/db_backup_restore.bats` (mocked `mariadb`) and
`tests/unit/php_temp_dirs.bats` (mocked `mkdir`/`chmod`/`chown`).

The updater helpers in `lib/lemper-update.sh` are tested the same way. Source the
plugin with `LEMPER_UPDATE_LIB_ONLY=true` (otherwise it runs its entry point) and
stub `requires_root`; point `PHP_ETC_DIR` at a temp tree and export
`LEMPER_BACKUP_DIR` so mitigation tests never touch `/etc`:

```bash
requires_root() { :; }
PROG_NAME="lemperctl"
LEMPER_UPDATE_LIB_ONLY=true
. "${REAL_BASE_DIR}/lib/lemper-update.sh"
php_mitigate_pool_file "${pool}" 8.4
```

See `tests/unit/update_helpers.bats` for version comparison, branch
classification, and idempotent pool-rewrite coverage.

### 5.4 Writing Integration Tests (bats-core)

```bash
# tests/integration/site_create.bats
#!/usr/bin/env bats

@test "lemperctl site add creates vhost config" {
    run lemperctl site add -d test.example -f default -w /tmp/test-webroot
    [ "$status" -eq 0 ]
    [ -f /etc/nginx/sites-available/test.example.conf ]
}
```

### 5.5 Test Environment

Tests that perform real installation should run in:
- GitHub Actions runner (`ubuntu-latest`)
- Docker container with `--privileged` for systemd
- Local Vagrant/VM for interactive development

Mock-based unit tests can run anywhere Bash is available.

### 5.6 New Install/Remove Scripts

To add a new component (e.g., `newtool`):

1. **Create installer**: `scripts/install_newtool.sh` — follow the pattern in
   `scripts/install_fail2ban.sh` or `scripts/install_crowdsec.sh`. Source
   `utils.sh`, use `run` wrapper, guard with `AUTO_INSTALL` and
   `FORCE_INSTALL` checks.
2. **Create remover**: `scripts/remove_newtool.sh` — follow
   `scripts/remove_crowdsec.sh`. Guard with `AUTO_REMOVE` and
   `FORCE_REMOVE` checks.
3. **Add config**: Add `[newtool]` section to `.env.dist` with
   `INSTALL_NEWTOOL=false` default.
4. **Wire into stacks**: Add sourcing blocks to
   `lib/core/registry.sh` for component metadata and install/remove recipes.
   `lib/runtime/stack/entry.sh` owns profile parsing; `recipe.sh` owns full-stack orchestration.
5. **CI**: Add `sed` line in `.github/workflows/main.yml` to toggle the
   flag for testing.

### 5.7 Adding New CLI Subcommands

To add a new CLI subcommand (e.g., `lemperctl db backup`):

1. **Create plugin file**: `lib/lemper-<command>-<subcmd>.sh` with
   `init_lemper_<command>_<subcmd>()` function.
2. **Register in dispatcher**: Add the subcommand to the case statement
   in `lib/lemper-<command>.sh` (the dispatcher).
3. **Install plugin**: Add to `scripts/install_tools.sh` copy list →
   `/etc/lemper/cli-plugins/`.
4. **Update help**: Add the subcommand to `cmd_help()` in the dispatcher.
5. **Test**: Add structure test in `tests/test_structure.bats`.
6. **Document**: Update help text in `bin/lemper-cli.sh`.

---

## 6. Configuration System

### 6.1 `.env` File Format

The `.env` file uses a pseudo-INI format with sections. **Do not commit `.env`** — it is
in `.gitignore`. Use `.env.dist` as the template.

```ini
[installer]
AUTO_INSTALL=true
FORCE_INSTALL=false

[lemper]
ENVIRONMENT="production"
LEMPER_USERNAME="lemper"
LEMPER_PASSWORD=""  # Blank = auto-generated
```

### 6.2 Configuration Loading

Configuration is loaded by `scripts/utils.sh` through `safe_parse_dotenv()`. It skips
comments/sections, splits each line on the first `=`, validates the key name, and exports
the value without `eval`:

```bash
while IFS=$'\t' read -r key value; do
    export "${key}=${value}"
done < <(safe_parse_dotenv "${ENVFILE}")
```

Because every key present in `.env` is re-exported, values in the file win over
caller-supplied environment variables. Use variables that do not appear in `.env.dist`
(such as `LEMPER_PROFILE` and `LEMPER_MEMORY_MB`) for one-off overrides.

### 6.3 Resource Profile Knobs

| Variable | Default | Effect |
|---|---|---|
| `SERVER_PROFILE` | `auto` | Forces `micro`, `small`, `medium`, or `large` |
| `LEMPER_PROFILE` | unset | Environment-only override (beats `SERVER_PROFILE`) |
| `PHP_FPM_MAX_CHILDREN` | unset | Explicit `pm.max_children` (skips RAM budget) |
| `PHP_MEMORY_LIMIT` | `256M` | Per-request limit; drives worker-size estimate |
| `OPCACHE_MEMORY_MB` | unset | Overrides profile-derived opcache size |
| `NGINX_ETAG` | `off` | `on`/`off` for the `etag` directive |
| `NGINX_RATE_LIMITING` | `false` | Enables `limit_req`/`limit_conn` on all vhosts |
| `DENY_ARCHIVE_FILES` | `false` | Denies `.zip`/`.tar`/`.gz`/… in web roots |
| `SESSION_COOKIE_SECURE` | `false` | Sets `session.cookie_secure` on all pools |

The installer also writes `/etc/mysql/mariadb.conf.d/99-lemper-tuning.cnf` with an
`innodb_buffer_pool_size`, `max_connections`, `table_open_cache`, and
`performance_schema` value derived from the active profile (`calc_mariadb_sizing()`).
Re-run the installer after changing `SERVER_PROFILE` to regenerate it.

### 6.3 Runtime Config

During installation, credentials and runtime settings are written to
`/etc/lemper/lemper.conf` (mode 0600, root-only). CLI plugins read from this file at
startup.

---

## 7. Adding a New Feature

### 7.1 Adding a New CLI Command

1. Create a new plugin script in `lib/`, e.g., `lib/lemper-monitor.sh`
2. Start from the canonical header (copyright 2014-2026), then declare
   command metadata and the direct-access guard:

```bash
#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - <Title>                                                    |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2026 MasEDI.Net (https://masedi.net/lemper)          |
# +-------------------------------------------------------------------------+
# | ... license text and Authors block ...                                  |
# +-------------------------------------------------------------------------+

CMD_PARENT="${PROG_NAME}"
CMD_NAME="monitor"

if [[ "$(type -t requires_root)" != "function" ]]; then
    echo "Direct access to this script is not permitted."
    exit 1
fi
```

3. Implement `<cmd>_show_usage()` and `init_lemper_monitor()` functions, and
   call `init_lemper_monitor "$@"` unconditionally at the end of the file.
   Handle `-h`/`--help` and `-v`/`--version` before any side effects.
4. Add the plugin to `scripts/install_tools.sh` and to the mapping in
   `update_lemper_tooling()` in `lib/lemper-update.sh`:

```bash
run cp -f lib/lemper-monitor.sh /etc/lemper/cli-plugins/lemper-monitor && \
run chmod ugo+x /etc/lemper/cli-plugins/lemper-monitor
```

5. Write unit tests in `tests/unit/monitor.bats` (see section 5.3).
6. Add ShellCheck to CI config.

### 7.2 Adding a New Service Installer

1. Create `scripts/install_<service>.sh` following the standard guard pattern.
2. Add the sourcing call in `install.sh` (after existing service installs).
3. Create `scripts/remove_<service>.sh` and add it to `remove.sh`.
4. Add `.env` config defaults to `.env.dist`.
5. Add tests.

---

## 8. CI/CD Pipeline

### 8.1 Current Pipeline (`.github/workflows/main.yml`)

The CI pipeline runs on every push/PR to `2.x.x` and `master` branches:

1. **Setup:** Copies `.env.dist` → `.env`, adjusts config for CI environment.
   Toggled for CI: `REDIS_BACKEND="valkey"`, `INSTALL_CROWDSEC=true`,
   `ACME_WILDCARD=true`, `INSTALL_MODSEC=true`, `ENCRYPT_CONFIG_AT_REST=true`.
2. **ShellCheck:** Runs `shellcheck -s bash -x` on every script file — **exit 0**.
3. **Bats Tests:** Runs `bats tests/ tests/unit/` — see current CI/Bats results.

CI includes Ubuntu 24.04, a Debian 12 container, FTP build jobs, and a version-tag release workflow.

### 8.2 Formatting and coverage

`.editorconfig` defines editor defaults. `shfmt` checks the explicit file list in
`tools/shfmt-files.txt`; add new modules to that list and format only those files.
Existing Bashate/ShellCheck checks still cover all scripts. This avoids an unrelated
repository-wide formatting diff.

```bash
bash scripts/check_format.sh          # check; requires shfmt (CI package 3.8)
bash scripts/check_format.sh --write  # format the opted-in files
bash scripts/test_coverage.sh         # requires Bash 5+, Bats and jq
```

Use Linux/Podman on macOS. With the project mounted read-only as `/source`, run
checks there and pass `/run/coverage` to `test_coverage.sh` for writable output.
Copy the files back with `podman cp` if needed. Coverage runs the synthetic Bats
suite with explicit DEBUG function-entry instrumentation. It records only source
paths and function names, never command text or arguments; temporary traces are
deleted. JSON/Markdown artifacts cover the files declared in
`tests/coverage_scope.txt`. This is function-entry coverage, not line/branch coverage
or evidence of live installation. The `formatting-and-coverage` CI job publishes
these artifacts; generated `/coverage/` is ignored, while documentation stays tracked.

Current CI also includes Debian/Ubuntu validation, host/dependency audits and
version-tag release automation. `bandit` targets Python; `shellspec` is a testing
framework. Neither is treated as a shell security scanner.

Installer component counters estimate remaining time from completed work when
`PROGRESS_ETA=true` and stdout is a terminal; component durations can vary. Spinners
show elapsed time and return cleanly under errexit. Configuration archive restoration
uses optional `pv` byte/rate/ETA feedback when `TRANSFER_PROGRESS=true`, stderr is a
terminal, and `pv` is installed (`sudo apt-get install pv`). Without it, restoration
uses the same validated archive stream without progress output. Both switches default
to true; non-TTY step output remains plain and dry runs emit no archive bytes.

### 8.3 Hosting quota UAT (issue #39)

Read `tests/uat/p3_acceptance.sh` first. The fixture requires a disposable systemd
container, a read-only project mount, an authorization marker, and a loop-backed
ext4 `/home`. Privilege is required specifically to create/mount this disposable
filesystem and exercise kernel quotas. Do not run this on a workstation/live server.
The CI `hosting-quota-uat` job uses the same procedure on Ubuntu 24.04 and Debian 12.

```bash
podman build -f tests/uat/Containerfile -t lemper-p3-uat tests/uat
podman run -d --name lemper-p3-uat --privileged --systemd=always \
  --cgroupns=private --hostname p3.lemper-uat.test --cpus 2 --memory 2g \
  --tmpfs /run --tmpfs /tmp -v "$PWD:/source:ro" lemper-p3-uat
podman exec lemper-p3-uat bash -c '
  set -e
  apt-get update -qq
  apt-get install -q -y quota pv
  touch /run/lemper-p3-uat-authorized
  truncate -s 192M /run/p3-quota.img
  mkfs.ext4 -q -O quota /run/p3-quota.img
  quota_loop=$(losetup -f)
  [[ "$quota_loop" =~ ^/dev/loop[0-9]+$ ]] || exit 1
  [[ -e "$quota_loop" ]] || mknod "$quota_loop" b 7 "${quota_loop#/dev/loop}"
  mount -o loop,usrquota /run/p3-quota.img /home
  bash /source/tests/uat/p3_acceptance.sh
'
podman exec lemper-p3-uat umount /home
podman stop --time 10 lemper-p3-uat
```

Use a fresh container for each acceptance run; the test deliberately retains
synthetic accounts/data. No modules/kernel packages are installed to hide a
missing capability. Kernel EDQUOT failures, active-plan protection, downgrade
rejection, locked failed provisioning, recovery, retained data and actual `pv`
TTY transfer are checked. Loop device nodes created in a container use only the
unused device chosen by `losetup -f`; unmount releases the loop when finished.

---

## 9. Common Pitfalls

### 9.1 Configuration is data

Core configuration/schema modules validate values and load literal key/value
pairs. Never reintroduce eval or shell-source loading of private configuration.
Compatible runtime loading accepts legacy extension keys but refuses shell and
source-path control variables; config check and full installation use stricter
validation.

### 9.2 `exit` in Sourced Scripts

Scripts in `scripts/` and `lib/` are sourced, not executed. Calling `exit` in these scripts
will kill the parent process. Use `return` instead — except inside subcommand handler
functions, where `exit 0` is acceptable.

### 9.3 Unquoted Variables in `sed`

Domain names and IP addresses are passed to `sed` replacement strings. This is a potential
injection vector if the input contains shell metacharacters. Always validate input first
(`validate_fqdn`, `validate_ipv4`).

### 9.4 `run` vs Direct Execution

Always use `run` for commands that modify the system. The `run` function respects
`DRYRUN` mode and provides centralized error handling.

### 9.5 The `fial` Typo

> **✅ Fixed (v2.7.2):** The `fial` typo was corrected to `fail` in Phase 0
> (commit `534c1cf`). The instances were in `lib/lemper-create.sh:957` and
> `lib/lemper-db.sh:593`. This pitfall section is retained for historical reference.

---

## 10. Release Process

### 10.1 Versioning

LEMPer uses [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`

| Increment | Meaning |
|---|---|
| MAJOR | Breaking changes (e.g., dropped PHP 5.6 support) |
| MINOR | New features (backward-compatible) |
| PATCH | Bug fixes, security patches |

### 10.2 Release Steps

1. Prepare a `release/v4.0.0` branch and commit the reviewed working tree.
2. Ensure `bin/lemper-cli.sh` declares `PROG_VERSION="4.0.0"` and
   `CHANGELOG.md` contains the v4 entry; set its release date when publishing.
3. Run the Linux checks and fresh-container bootstrap UAT described in
   [the v4 release guide](docs/RELEASE_V4.md). Candidate CI and tagged releases
   share `release-acceptance.yml`, which verifies reproducibility and performs
   exact-archive installation/removal on Ubuntu 24.04/26.04 and Debian 12.
4. From a clean committed checkout, build locally:

   ```bash
   bash scripts/build_release.sh 4.0.0 /tmp/lemper-release-v4
   ```

   Run the builder in Linux on macOS, using a disposable Podman fixture; it needs
   GNU `sha256sum`. The builder produces the archive, archive SHA256, `get-lemper`, and bootstrap
   SHA256. It refuses dirty checkouts and mismatched versions.
5. Review the artifacts and release limitations. After publishing is authorized,
   push the reviewed release commit and annotated `v4.0.0` tag. The tag workflow
   requires archive acceptance, repeats lint/Bats checks and publishes all four assets.
6. Verify the published checksums and README one-line commands on a fresh
   disposable server before announcing the release.

---

## 11. Useful Commands

```bash
# Run shellcheck on all scripts
shellcheck -s bash -x install.sh remove.sh lemper.sh bin/lemper-cli.sh \
    lib/lemper-*.sh lib/core/lemper-stacks.sh scripts/*.sh \
    scripts/nginx/*.sh tests/*.bats

# Run all bats tests
bats tests/ tests/unit/

# Run in Podman container (macOS → Linux)
podman run --rm -v "${PWD}:/lemper:ro" -w /lemper ubuntu:24.04 \
    bash -c 'apt-get update -qq && apt-get install -qq -y shellcheck bats && shellcheck -s bash install.sh scripts/*.sh scripts/nginx/*.sh && bats tests/ tests/unit/'

# Dry-run install in a container
podman run --rm --privileged \
    -v "${PWD}:/lemper:rw" -w /lemper ubuntu:24.04 bash -c '
        apt-get update -qq && \
        cp .env.dist .env && \
        sed -i "s/AUTO_INSTALL=false/AUTO_INSTALL=true/" .env && \
        sed -i "s/INSTALL_NGINX=true/INSTALL_NGINX=false/" .env && \
        DRYRUN=true bash install.sh
    '
```

---

## 12. Resources

- [LEMPer GitHub Repository](https://github.com/joglomedia/LEMPer)
- [LEMPer Issue Tracker](https://github.com/joglomedia/LEMPer/issues)
- [ShellCheck Wiki](https://github.com/koalaman/shellcheck/wiki)
- [shunit2 Documentation](https://github.com/kward/shunit2)
- [Bash Hackers Wiki](https://wiki.bash-hackers.org/)
- [GNU Bash Manual](https://www.gnu.org/software/bash/manual/)

## CLI/module contracts

Ubuntu 26.04 support uses the maintained Sury PHP driver, native MariaDB 11.8
and a Dovecot 2.4 template; see [the Resolute guide](docs/UBUNTU_26_04.md).
The `php-repository-uat` matrix checks real PHP installation/update on Ubuntu
22.04/24.04/26.04 and Debian 12. Its fixture requires a disposable systemd host,
a read-only `/source` mount and `/run/lemper-php-repository-uat-authorized`.

Repository-owned script functionality stays in Bash, including extensionless
wrappers and test clients. See [the Bash audit](docs/BASH_SCRIPT_AUDIT.md) for the
inventory and native tools. Third-party services keep their upstream runtimes.

Prefer `lemperctl` and preserve `lemper-cli`, legacy flags and site aliases.
Command exports, aliases, components and recipes belong in
`lib/core/registry.sh`; do not add another installer/updater mapping.

Use cases belong in `lib/runtime/`, drivers in `lib/services/`, and
self-dispatching legacy boundaries in `lib/compat/`. New modules define functions
without dispatching when sourced. Return statuses, use `lemper_exec` for
mutations, and pass literal arrays and explicit inputs/context.

Code installation uses `lib/core/deployment.sh`. Config backup excludes code
compatibility links and retains ownership metadata. Distinguish supported PHP
installation targets from installed management/removal targets. Run
`tests/unit/alignment_contracts.bats` and required checks when changing contracts.

## v4 stack installation entry points

`install.sh`, `remove.sh`, `update.sh`, and `lemper.sh` delegate to
`lib/runtime/stack/entry.sh`. Public `lemperctl stack ... --all` operations use
that same adapter before installed configuration is required. Per-service
commands retain their driver and ownership checks. Legacy installer flags and
updater setup are isolated in function-only `lib/compat/installer.sh` and
`updater.sh` modules; execution is contained in child shells.

Profiles merge defaults and installed credentials, then explicit settings.
Empty template secrets do not erase generated credentials. `--yes` participates
in SSH-key validation; `--dry-run` and profile `DRYRUN=true` return before any
host initialization. Explicit installs back up and store their effective profile.
`--minimal` disables optional services and `INSTALL_WEB_ADMIN`, without changing
SSH or firewall choices. Disabled component scripts are not sourced.

## Prioritized roadmap follow-through UAT

The `priority-followthrough-uat` job runs `tests/uat/priority_acceptance.sh` on
Ubuntu 24.04 and Debian 12. Read the fixture before running it. It installs a CLI
snapshot, provisions only synthetic users/databases/certificates, tests owned-domain
DB commands, verifies real signed repository indexes and checks the native Bun
release binary. Ubuntu also compiles Nginx 1.30.7 against checksummed OpenSSL 3.5.9,
validates QUIC configuration and performs verified HTTPS with that exact binary.

Run it only in a fresh disposable systemd/Podman container, with the project
mounted read-only as `/source` and `/run/lemper-priority-uat-authorized` present.
Prepare the distribution's nginx/php-fpm/php-cli/mariadb-server/cron/gnupg packages;
for compilation also install build-essential/libpcre2-dev/zlib1g-dev/libssl-dev.
The complete container setup is in `.github/workflows/main.yml`.

```bash
podman exec lemper-priority-uat bash -c '
  touch /run/lemper-priority-uat-authorized
  cp /source/tests/uat/priority_acceptance.sh /run/priority-acceptance.sh
  bash /run/priority-acceptance.sh --build-tls
'
podman stop --time 10 lemper-priority-uat
```

Always run a frozen copy of the fixture: editing a mounted Bash script while it
runs can change read offsets. The fixture also reads subsequent helpers/templates
from the immutable CLI snapshot. Compilation uses `/var/tmp`, not the limited
memory-backed `/run`; runtime SSL builds omit unused OpenSSL test executables.
Do not copy private `.env` files into UAT or disable TLS/signature checks to pass it.

### Application capability acceptance (A3)

Read `tests/uat/application_capabilities_acceptance.sh` before execution. It
requires a designated disposable Ubuntu 24.04 systemd host, `/source` mounted
read-only, and `/run/lemper-a3-uat-authorized`. Prepare Nginx, PHP 8.3 CLI/FPM,
Composer, PHP curl/intl/mbstring/xml/zip/gd/imap/mysql/sockets, Git, rsync, unzip and wget, with a
synthetic LEMPer configuration. The suite snapshots the CLI, backs up the host's
Nginx configuration, and installs the tracked templates needed by site creation.
It creates synthetic users/sites and downloads complete Mautic/Roundcube releases
and a real CodeIgniter project. Setup-page tests use loopback; additional checks
deny non-loopback setup access and arbitrary PHP/private-file requests.

```bash
# Run only inside the explicitly designated disposable host.
podman exec lemper-apps-uat bash -e -c '
  touch /run/lemper-a3-uat-authorized
  cp /source/tests/uat/application_capabilities_acceptance.sh /run/apps-acceptance.sh
  bash /run/apps-acceptance.sh
'
podman stop --time 10 lemper-apps-uat
```

An optional alphanumeric suffix of up to eight characters gives a fresh isolated
workspace when investigating a failed run. Logs stay under the mode-0700
`/var/tmp/lemper-a3-uatSUFFIX` directory. Checks distinguish installation rejection
from working manual PHP vhosts and verify Mautic/Roundcube/CodeIgniter files,
ownership, Nginx configuration, repeat preservation and HTTP. Other automatic installers need their own deployment
checks; see [APPLICATIONS.md](docs/APPLICATIONS.md).

### Additional application UAT

`tests/uat/additional_applications_acceptance.sh` deploys the six additional
automatic apps and a manual XenForo vhost in a designated disposable systemd
host. Read it first. Prepare PHP 8.3/FPM with the required extensions (including
BCMath for OJS), Composer, Git, MariaDB, Nginx, jq and libxml2-utils (xmllint).
Mount the checkout read-only
at `/source` and use `/run/lemper-additional-apps-uat-authorized`.

```bash
podman exec lemper-apps-uat bash -e -c '
  touch /run/lemper-additional-apps-uat-authorized
  cp /source/tests/uat/additional_applications_acceptance.sh /run/additional-apps.sh
  bash /run/additional-apps.sh apps
'
```

The optional suffix isolates users/domains and private logs. After an investigated
failure, `SUFFIX --resume` refreshes only owned disposable fixtures and retains
previous logs. The phpList HTTP fixture provisions its own synthetic database
using a protected password file; production deployment leaves database setup to
the operator. Routing probes back up/restore real MyBB and Nextcloud entry files,
and use synthetic XenForo PHP to test friendly URLs without a license artifact.
This checks installation/routing, not authenticated mail/forum/cloud workflows.
