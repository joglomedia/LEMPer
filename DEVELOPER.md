# LEMPer Developer Guide

> **Version:** 3.0.0 (proposed)
> **Last Updated:** 2026-10-22
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
| EditorConfig | — | See `.editorconfig` (to be added in v3.0) |

> **macOS developers:** Use Podman Machine to test scripts in a real Linux environment.
> macOS `sed -i` and `grep -P` behave differently from GNU/Linux. Podman eliminates
> this gap (see [§3.4](#34-container-based-testing-with-podman-machine)).

### 1.2 System Requirements (Target)

- Debian 12 or Ubuntu 22.04/24.04 (amd64 or arm64)
- Root/sudo access for installation testing
- At least 2GB RAM, 20GB disk (swap auto-created for low-RAM systems)

---

## 2. Project Structure

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the full architecture overview. The key
directories for development:

| Directory | Purpose | Files to Edit |
|---|---|---|
| `bin/` | CLI entry point | `lemper-cli.sh` |
| `lib/` | CLI plugins + library code | `lemper-*.sh` |
| `scripts/` | Installation & removal scripts | `install_*.sh`, `remove_*.sh`, `server_*.sh`, `utils.sh` |
| `etc/` | Configuration templates | `*.conf`, `*.ini`, service files |
| `share/` | Static assets | HTML error pages, index, tool configs |
| `tests/` | Unit & integration tests | New in v3.0 |
| `docs/` | Documentation | This guide and companions |

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

# 3. Unit tests (when applicable)
cd tests && ./run_tests.sh

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
# From the LEMPer project root:
podman run --rm \
    -v "${PWD}:/lemper:ro" \
    -w /lemper \
    ubuntu:24.04 bash -c '
        apt-get update -qq && \
        apt-get install -qq -y shellcheck bats > /dev/null 2>&1 && \
        shellcheck -s bash -x \
            install.sh remove.sh lemper.sh \
            bin/lemper-cli.sh \
            lib/lemper-*.sh lib/core/lemper-stacks.sh \
            scripts/install_*.sh scripts/remove_*.sh scripts/utils.sh \
            scripts/server_*.sh scripts/nginx/*.sh \
            tests/*.bats && \
        bats tests/ tests/unit/
    '
```

#### 3.4.3 Run Full Installation (Dry-Run)

```bash
podman run --rm --privileged \
    -v "${PWD}:/lemper:rw" \
    -w /lemper \
    ubuntu:24.04 bash -c '
        apt-get update -qq && apt-get install -qq -y shellcheck > /dev/null 2>&1 && \
        cp .env.dist .env && \
        sed -i "s/AUTO_INSTALL=false/AUTO_INSTALL=true/" .env && \
        sed -i "s/ENVIRONMENT=\"production\"/ENVIRONMENT=\"local\"/" .env && \
        sed -i "s/INSTALL_NGINX=true/INSTALL_NGINX=false/" .env && \
        sed -i "s/INSTALL_PHP=true/INSTALL_PHP=false/" .env && \
        DRYRUN=true bash install.sh
    '
```

#### 3.4.4 macOS vs Linux Portability Gotchas

| Construct | macOS (BSD) | Linux (GNU) | Portable Alternative |
|---|---|---|---|
| `sed -i 's/x/y/g' file` | Requires `sed -i '' '...'` | `sed -i 's/x/y/g' file` | Wrap in `sed_inplace()` helper |
| `grep -P 'pattern'` | Not supported | Supported | Use `grep -E` (ERE) or `perl` |
| `date +%N` | Nanoseconds always 0 | Real nanoseconds | Use `gdate` from coreutils on macOS |
| `stat -f` | BSD `stat -f` | GNU `stat -c` | Check `uname` or use `stat --format=` |

> **Current status:** The codebase still uses GNU `sed -i` (210 usages across 20 files)
> and was migrated from `grep -oP` to `grep -qE` (ERE) during Phase 2. The `sed -i`
> portability is tracked as **STACK-08** / **Task 2.35** in the v3.5.0 roadmap.

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
| **bats-core** | Structural, syntax, and mock-based unit tests | **97 tests** (primary) |
| **shunit2** | Legacy unit tests (still present) | `shunit2/run_test.sh` |

### 5.2 Running Tests

```bash
# Full test suite (bats)
bats tests/ tests/unit/

# ShellCheck on all scripts (must pass with exit 0)
shellcheck -s bash -x \
    install.sh remove.sh lemper.sh \
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

### 5.4 Writing Integration Tests (bats-core)

```bash
# tests/integration/site_create.bats
#!/usr/bin/env bats

@test "lemper-cli site add creates vhost config" {
    run lemper-cli site add -d test.example -f default -w /tmp/test-webroot
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
   `lib/core/lemper-stacks.sh` in both `lemper_install()` and
   `lemper_remove()`.
5. **CI**: Add `sed` line in `.github/workflows/main.yml` to toggle the
   flag for testing.

### 5.7 Adding New CLI Subcommands

To add a new CLI subcommand (e.g., `lemper-cli db backup`):

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
2. Add the `CMD_NAME` and direct-access guard:

```bash
#!/usr/bin/env bash
CMD_PARENT="${PROG_NAME}"
CMD_NAME="monitor"

if [[ "$(type -t requires_root)" != "function" ]]; then
    echo "Direct access to this script is not permitted."
    exit 1
fi
```

3. Implement `show_usage()` and `init_lemper_monitor()` functions.
4. Add the plugin to `scripts/install_tools.sh`:

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
3. **Bats Tests:** Runs `bats tests/ tests/unit/` — **97/97 tests pass**.

**CI runs on `ubuntu-latest`** with ShellCheck v0.10.0 and bats-core 1.14.0.

### 8.2 Planned v3.0 Enhancements

| Enhancement | Description |
|---|---|
| Multi-distro matrix | Test on Debian 12 + Ubuntu 24.04 |
| Security scanning | Add `shellspec` or `bandit` for shell security |
| Dependency audit | Check for outdated package versions |
| Release automation | Semantic versioning with git tags + changelog |
| Coverage reporting | Track test coverage of critical functions |
| Linting gate | `bashate` + `shfmt` for formatting enforcement |

---

## 9. Common Pitfalls

### 9.1 `eval` in Configuration Loading

The config loader uses `eval` to source key=value pairs from `.env`/`.env.conf`:

```bash
source <(grep -v '^#' "${ENVFILE}" | grep -v '^\[' | \
    sed -E 's|^(.+)=(.*)$|: ${\1=\2}; export \1|g')
```

> **⚠️ SECURITY:** This is a known injection vector if config values contain shell
> metacharacters. **Status:** Partially addressed in v3.4.0 — `lib/lemper-encrypt.sh`
> provides `load_config()` which adds decryption support but still uses `eval` internally.
> **Planned fix (v3.5.0, Task 2.33):** Replace with a safe `while IFS='=' read` parser.

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

1. Create a release branch: `git checkout -b release/v3.0.0`
2. Update version strings in all files (`PROG_VERSION="3.0.0"`)
3. Update changelog (`CHANGELOG.md`)
4. Run full test suite
5. Merge to `master` and tag: `git tag -a v3.0.0 -m "Release v3.0.0"`
6. Push tag: `git push origin v3.0.0`
7. Create GitHub Release with changelog

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
