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
| bats-core | 1.5+ | Integration/CLI testing (planned v3.0) |
| EditorConfig | — | See `.editorconfig` (to be added in v3.0) |

### 1.2 System Requirements (Target)

- Debian 11/12 or Ubuntu 20.04/22.04/24.04 (amd64 or arm64)
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

# 2. Shell formatting (bashate-style checks)
# (In v3.0, a .editorconfig will enforce tab-vs-space, line length, etc.)

# 3. Unit tests (when applicable)
cd tests && ./run_tests.sh

# 4. Verify .env is not tracked
git status --porcelain | grep '.env' && echo "ERROR: .env is tracked!" && exit 1
```

> **Note:** The CI pipeline runs these checks automatically. A failing check blocks the PR.

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

| Framework | Purpose |
|---|---|
| **shunit2** | Unit tests for individual functions |
| **bats-core** | CLI integration tests (planned v3.0) |

### 5.2 Running Tests

```bash
# Unit tests (shunit2)
bash shunit2/run_test.sh

# Full test suite (planned v3.0)
cd tests
./run_all.sh

# ShellCheck only
shellcheck -s bash bin/lemper-cli.sh lib/lemper-*.sh scripts/*.sh scripts/nginx/*.sh
```

### 5.3 Writing Unit Tests

Tests live in `tests/unit/`. Each test file corresponds to a source file:

```bash
# tests/unit/test_utils.sh
#!/usr/bin/env bash
# shellcheck source=scripts/utils.sh
. scripts/utils.sh

test_validate_fqdn_valid() {
    assertEquals "true" "$(validate_fqdn 'example.com')"
}

test_validate_fqdn_invalid() {
    assertEquals "false" "$(validate_fqdn 'not_a_domain')"
}

# Load shunit2 at the end
. /usr/local/bin/shunit2
```

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

Configuration is loaded by `scripts/utils.sh` (for installer scripts) and
`bin/lemper-cli.sh` (for CLI plugins) via the following pattern:

```bash
source <(grep -v '^#' "${ENVFILE}" | grep -v '^\[' | \
    sed -E 's|^(.+)=(.*)$|: ${\1=\2}; export \1|g')
```

> **⚠️ SECURITY WARNING (v3.0 planned fix):** This `eval`-based loading is a known
> injection vector. In v3.0, this will be replaced with a safe, non-eval parser.

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

5. Write unit tests in `tests/unit/test_monitor.sh`.
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

1. On push/PR to `2.x.x` or `master`:
   - Checkout code
   - Set up `.env` for CI
   - Install ShellCheck v0.10.0 + shunit2
   - Run ShellCheck on all scripts
   - Run `server_cleanup.sh`, `install_dependencies.sh`, and `run_test.sh`

### 8.2 Planned v3.0 Enhancements

| Enhancement | Description |
|---|---|
| Multi-distro matrix | Test on Debian 11, 12 + Ubuntu 22.04, 24.04 |
| Security scanning | Add `shellspec` or `bandit` for shell security |
| Dependency audit | Check for outdated package versions |
| Release automation | Semantic versioning with git tags + changelog |
| Coverage reporting | Track test coverage of critical functions |
| Linting gate | `bashate` + `shfmt` for formatting enforcement |

---

## 9. Common Pitfalls

### 9.1 `eval` in Configuration Loading

Never use `eval` or `source <(...)` with user-controlled input. The current dotenv loader
is flagged for replacement in v3.0.

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

There are two known instances of `fial` (typo for `fail`) in the codebase:
- `lib/lemper-create.sh:957`
- `lib/lemper-db.sh:593`

These should be fixed as part of the v3.0 cleanup.

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
# Run shellcheck on all files
find . -name '*.sh' -not -path './.git/*' | xargs shellcheck -s bash

# Run only unit tests
bash tests/unit/run_all.sh

# Dry-run install in a container
docker run -it --rm ubuntu:24.04 bash
# ... inside container ...
git clone https://github.com/joglomedia/LEMPer.git && cd LEMPer
cp .env.dist .env
sed -i 's/AUTO_INSTALL=true/AUTO_INSTALL=false/' .env
DRYRUN=true ./install.sh
```

---

## 12. Resources

- [LEMPer GitHub Repository](https://github.com/joglomedia/LEMPer)
- [LEMPer Issue Tracker](https://github.com/joglomedia/LEMPer/issues)
- [ShellCheck Wiki](https://github.com/koalaman/shellcheck/wiki)
- [shunit2 Documentation](https://github.com/kward/shunit2)
- [Bash Hackers Wiki](https://wiki.bash-hackers.org/)
- [GNU Bash Manual](https://www.gnu.org/software/bash/manual/)
