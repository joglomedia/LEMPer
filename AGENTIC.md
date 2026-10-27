# LEMPer — Agentic Guide for AI Assistants

> **Version:** 3.0.0 (proposed)
> **Last Updated:** 2026-10-22
> **Purpose:** This document provides structured guidance for AI agents (LLM-based coding
> assistants) working on the LEMPer codebase. It identifies common patterns, known
> pitfalls, and recommended approaches for task execution.

---

## 1. Codebase Overview for AI Agents

### 1.1 What LEMPer Is

LEMPer is a **Bash-based** tool that (1) installs a complete LEMP/LEMP server stack on
Debian/Ubuntu and (2) provides a runtime CLI (`lemper-cli`) for managing virtual hosts,
databases, SSL certificates, and supporting services.

The entire codebase is Bash. There are **no compiled languages**, **no package.json**,
and **no Python source files** in the repository. All logic is Bash scripts, INI-style
configuration templates, and static Nginx/Redis/MariaDB config files.

### 1.2 Key Constraints

| Constraint | Implication |
|---|---|
| All code is Bash | Use `shellcheck -s bash`, not `bashate` or Python linters |
| Sourced, not executed | Many scripts are `source`d — `exit` kills the parent |
| Runs as root | Scripts modify `/etc`, use `systemd`, create users |
| No external dependencies | Only depends on `bash`, `coreutils`, `openssl`, `curl`, `git` |
| Git-tracked templates | Configs in `etc/` are static templates copied to target |

---

## 2. File Categories & Their Patterns

### 2.1 Entry Points (Executable Scripts)

| File | Role | Exit allowed? |
|---|---|---|
| `install.sh` | Standalone installer | ✅ Yes |
| `remove.sh` | Standalone uninstaller | ✅ Yes |
| `lemper.sh` | Interactive installer/uninstaller with CLI args | ✅ Yes |
| `bin/lemper-cli.sh` | CLI dispatcher | ✅ Yes (at top level only) |

**Pattern:** These call functions from `scripts/utils.sh` and source `scripts/install_*.sh`.

### 2.2 Shared Library

| File | Role | Exit allowed? |
|---|---|---|
| `scripts/utils.sh` | Core helpers: `run()`, `info()`, `error()`, `success()`, config loader, OS detection | ❌ No (sourced) |
| `lib/lemper-account.sh` | Account creation (both sourceable + directly callable) | Mixed |

**Pattern:** Contains the `run()` function that respects `DRYRUN`. All system-modifying
commands must go through `run()`.

### 2.3 CLI Plugins (lib/)

| File | Command | Subcommands |
|---|---|---|
| `lib/lemper-site.sh` | `site` | Dispatches to create/manage |
| `lib/lemper-create.sh` | `site add` / `site create` | Full vhost + framework setup |
| `lib/lemper-manage.sh` | `site mod` / `site manage` | Enable/disable SSL, cache, fail2ban, brotli |
| `lib/lemper-db.sh` | `db` | account, create, drop, export, import, query |
| `lib/lemper-selfssl.sh` | `selfssl` | Generate self-signed SSL |
| `lib/lemper-fixpermission.sh` | `fixpermission` | Fix file permissions |
| `lib/lemper-bench.sh` | `bench` | Hardware, disk, and network benchmark (also in TUI) |
| `lib/lemper-account.sh` | (interactive, sourced standalone) | Interactive user creation |
| `lib/lemper-adduser.sh` | (interactive, sourced standalone) | Interactive user creation |

**Important:** Plugins in `lib/` are copied to `/etc/lemper/cli-plugins/` at install time
by `scripts/install_tools.sh`. They are then **sourced** by `bin/lemper-cli.sh`.

### 2.4 Installation Scripts (scripts/install_*.sh)

Each script follows this pattern:
1. Guard clause (include utils.sh if not already loaded)
2. `requires_root` + `preflight_system_check`
3. A main initialization function (e.g., `init_fail2ban_install`)
4. Top-level echo + function call

### 2.5 Nginx Sub-modules (scripts/nginx/*.sh)

These are **sourced** by `scripts/install_nginx.sh` (not executed directly). They contain
only function definitions, guarded by:

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script should be sourced, not executed directly."
    exit 1
fi
```

### 2.6 Configuration Templates (etc/)

Static files that are `cp`-ied to the target system during installation. These should
**not** be edited at runtime — they are templates.

---

## 3. Common Code Patterns to Recognize

### 3.1 The `run` Function

```bash
run SYSTEM_COMMAND   # DRYRUN-safe, error-checked
```

- If `DRYRUN=true` → prints `would run SYSTEM_COMMAND`, doesn't execute.
- If command fails → prints error and exits.
- **Always** use `run` for system-modifying commands.

**Exception:** `run` cannot handle pipes or complex shell constructs. For those, use:
```bash
run bash -c "complex pipeline command"
```

### 3.2 The Guard Clause

```bash
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    . "${BASE_DIR}/utils.sh"
    requires_root "$@"
    preflight_system_check
fi
```

This allows a script to be `source`d (sharing parent scope) or run standalone.
**Never remove this** — removing it breaks the standalone execution path.

### 3.3 Direct-Access Guard (CLI Plugins)

```bash
if [[ "$(type -t requires_root)" != "function" ]]; then
    echo "Direct access to this script is not permitted."
    exit 1
fi
```

This prevents a plugin from being run directly without the CLI dispatcher having loaded
the config and utility functions.

### 3.4 Dotenv Loading (Security Concern)

```bash
source <(grep -v '^#' "${ENVFILE}" | grep -v '^\[' | \
    sed -E 's|^(.+)=(.*)$|: ${\1=\2}; export \1|g')
```

This uses **process substitution + `eval`** to load `.env` into the environment.
It is a **known security issue** (v3.0 will replace it). When modifying config loading,
be very careful about quoting and escaping.

### 3.5 Variable Naming Conventions

| Pattern | Meaning |
|---|---|
| `UPPER_SNAKE_CASE` | Global/environment variables (from `.env` or computed) |
| `lowerCamelCase` | Local function variables |
| `CMD_PARENT` | CLI program name (e.g., `lemper-cli`) |
| `CMD_NAME` | Subcommand name (e.g., `site`, `db`) |
| `PROG_VERSION` | Version string (currently `"2.x.x"` placeholder) |

### 3.6 Framework Detection

In `lemper-create.sh`, the `FRAMEWORK` variable controls which vhost template and
auto-installer is used:

```
default, codeigniter, drupal, laravel, lumen, phalcon, symfony,
wordpress, wordpress-ms, woocommerce, owncloud, mautic, roundcube, sendy
```

Each framework has:
- A `create_vhost_<framework>()` function that outputs the Nginx server block
- A case branch in `init_lemper_create()` that handles download + install

### 3.7 Sudo Wrapper Pattern

```bash
sudo -E -H "$0" "$@"   # Re-exec self as root, preserving environment
```

Found in `lemper.sh`, `bin/lemper-cli.sh`, and `scripts/utils.sh`. The `-E` flag preserves
environment variables, `-H` sets HOME to root's home.

---

## 4. Known Issues & Gotchas (High-Priority)

### 4.1 `fial` Typo (Bug)

**Locations:**
- `lib/lemper-create.sh:957` — `fial` should be `fail`
- `lib/lemper-db.sh:593` — `fial` should be `fail`

**Impact:** When triggered, `fial` is an undefined function → causes `set -e` to abort
the script with an unhelpful error.

**Fix:** Replace `fial` → `fail` in both files.

### 4.2 `cgi.fix_pathinfo = 1` (Security)

**Location:** All PHP-FPM pool configs in `etc/php/*/fpm/pool.d/lemper.conf` and
`etc/php/*/fpm/pool.d/www.conf`.

**Impact:** Allows Nginx to pass arbitrary file paths to PHP, enabling path traversal
attacks (e.g., `/uploads/image.jpg/evil.php`).

**Fix:** Set to `0` in all configs. Already commented out correctly in `php.ini`
templates (`;cgi.fix_pathinfo=1`), but **enabled** in pool configs.

### 4.3 NOPASSWD:ALL Sudo (Security)

**Location:** `scripts/utils.sh:741`

```bash
run echo "${LEMPER_USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/90-lemper-users
```

**Impact:** The non-root `lemper` user has full passwordless root access.

**Fix:** Remove NOPASSWD, or restrict to specific commands.

### 4.4 Credential Exposure in stdout (Security)

**Location:** `install.sh:284-288`, `lemper.sh:194-280`

All passwords are printed to stdout at installation completion and optionally emailed.

**Impact:** Credentials visible in terminal scrollback, CI logs, and email inboxes.

**Fix:** Suppress credential output, require explicit `--show-credentials` flag.

### 4.5 `eval`-Based Config Loading (Security)

**Location:** `scripts/utils.sh:31`, `bin/lemper-cli.sh:55`

**Impact:** If `.env` or `lemper.conf` contains shell metacharacters, they are executed.

**Fix:** Replace with a safe parser (read line by line, use `declare -r`).

### 4.6 `FRAMEWORK^` in Error Messages

**Location:** `lib/lemper-manage.sh:250,289`

Uses Bash 4+ parameter expansion `^` to uppercase the first letter. This works but
produces inconsistent capitalization (e.g., "Wordpress" instead of "WordPress").

### 4.7 Dead Code

**Location:** `lemper.sh:526-527` — commented-out `./install.sh` and `./remove.sh` calls

### 4.8 CI References Non-Existent Variables — Resolved

The obsolete `NGX_PAGESPEED` sed line and the `PHP_LOADER="none"` reference are gone.
CI now toggles `INSTALL_PHP_LOADER=true`, which exists in `.env.dist`. PageSpeed was
removed entirely from the stack (issue #178).

---

## 5. Recommended Workflow for AI Agents

### 5.1 Before Making Changes

1. **Read the relevant files** thoroughly — understand the pattern before editing.
2. **Check ShellCheck compliance** of the file you're editing.
3. **Search for related code** using `grep -rn <pattern> lib/ scripts/ etc/` to find all
   occurrences of a variable or function.
4. **Read ARCHITECTURE.md and DEVELOPER.md** for context on conventions.

### 5.2 When Fixing Bugs

1. **Always verify the bug is real** — run the code path mentally or with a test.
2. **Look for duplicates** — bugs like `fial` may appear in multiple files.
3. **Fix all occurrences** — use `grep` to find every instance.
4. **Add a test** if the function is testable in isolation.

### 5.3 When Adding Features

1. **Follow existing patterns** — don't invent new conventions.
2. **Add to `.env.dist`** for any new configuration option.
3. **Add to `install.sh`** if it's a new installation component.
4. **Add CLI plugin entry** in `scripts/install_tools.sh` and the matching
   mapping in `lib/lemper-update.sh` if it's a new CLI command. Use the
   canonical 2014-2026 header, declare `CMD_PARENT`/`CMD_NAME`, and handle
   `-h`/`--help` and `-v`/`--version` before any side effects.
5. **Write tests** in `tests/unit/` or `tests/integration/`.
6. **Update shellcheck** if new shell patterns are introduced.

### 5.4 When Modifying Security-Critical Code

1. **Never introduce new `eval`** or `source <(...)`.
2. **Always validate input** before passing to `sed`, `openssl`, or SQL.
3. **Use `run`** for all system-modifying commands.
4. **Never `exit` in sourced scripts** — use `return`.
5. **Never print passwords** to stdout.

### 5.5 Testing Modifications

```bash
# Always run shellcheck on modified files
shellcheck -s bash <modified-files>

# Run unit tests
bash shunit2/run_test.sh

# For CLI logic tests, consider bats-core:
# tests/integration/<feature>.bats
```

---

## 6. File Quick Reference

| Pattern | Files | What to Look For |
|---|---|---|
| CLI dispatch | `bin/lemper-cli.sh` | How commands are routed to plugins |
| Vhost creation | `lib/lemper-create.sh` | `init_lemper_create()`, `create_vhost_*()`, `create_fpm_pool_conf()` |
| Vhost management | `lib/lemper-manage.sh` | `enable_vhost()`, `disable_vhost()`, `enable_ssl()`, `enable_brotli()` |
| Database ops | `lib/lemper-db.sh` | `db_operations()`, `cmd_account_*()`, `cmd_create()` |
| Account creation | `scripts/utils.sh` | `create_account()`, `delete_account()` |
| SSL generation | `lib/lemper-selfssl.sh`, `scripts/nginx/nginx_ssl_cert.sh` | `generate_selfsigned_ssl()`, `generate_selfsigned_cert()` |
| Nginx config | `etc/nginx/nginx.conf`, `etc/nginx/includes/*.conf` | `nginx.conf`, `rules_security.conf`, `ssl.conf`, `security_headers.conf` |
| PHP FPM pools | `etc/php/*/fpm/pool.d/*.conf` | `lemper.conf` template, `www.conf` |
| Service configs | `etc/mysql/`, `etc/redis/`, `etc/pure-ftpd/`, `etc/memcached/` | Database, cache, FTP configs |
| Systemd units | `etc/systemd/*.service` | Service file templates |
| CI | `.github/workflows/main.yml` | What tests run and on which distro |

---

## 7. AI-Specific Guidelines

### 7.1 Do NOT

- ❌ Assume the codebase uses a package manager other than `apt-get`.
- ❌ Introduce Python, Go, or Node.js as primary languages (this is a Bash project).
- ❌ Use `eval` with user-controlled input.
- ❌ Call `exit` in `lib/` scripts at the top level (only in subcommand functions).
- ❌ Modify files in `etc/` that are runtime configs on the target system — these are
  templates that get `cp`-ied during installation.
- ❌ Ignore ShellCheck warnings — they block CI.
- ❌ Commit the `.env` file — it is in `.gitignore` and contains secrets.

### 7.2 DO

- ✅ Check for the `fial` typo when grepping for error handling patterns.
- ✅ Search for all versions of a pattern (e.g., PHP pool configs span 8.2–8.5).
- ✅ Use `grep -rn` to find all references to a variable before renaming it.
- ✅ Follow the `run()` function convention for all system commands.
- ✅ Respect the guard clause pattern when creating new scripts.
- ✅ Update both `install.sh` , `remove.sh` , and `lemper.sh` when adding new installation steps
  (they contain similar but not identical logic).
- ✅ Add new CLI plugins to `scripts/install_tools.sh` install logic.

### 7.3 When in Doubt

1. Search the codebase: `grep -rn "suspicious_string" . --include="*.sh" --include="*.conf"`
2. Check the ARCHITECTURE.md for design intent.
3. Ask the human reviewer before making security-critical changes.
4. Run shellcheck on any modified file before proposing it.

---

## 8. Task Examples

### 8.1 Example: Fix `cgi.fix_pathinfo` Across All PHP Versions

```bash
# Find all occurrences
grep -rn "cgi.fix_pathinfo.*=.*1" etc/php/

# The fix: change `= 1` to `= 0` in pool configs only
# (php.ini already has it commented out)
# Target files: etc/php/*/fpm/pool.d/lemper.conf and etc/php/*/fpm/pool.d/www.conf

# Also check the generated pool config in lib/lemper-create.sh
grep -n "cgi.fix_pathinfo" lib/lemper-create.sh
```

### 8.2 Example: Add CrowdSec as a Modern Fail2ban Alternative

1. Create `scripts/install_crowdsec.sh` following the standard guard pattern.
2. Add `INSTALL_CROWDSEC` config to `.env.dist`.
3. Add sourcing call in `install.sh`.
4. Add `scripts/remove_crowdsec.sh` and add to `remove.sh`.
5. Write tests.

### 8.3 Example: Replace `eval`-Based Config Loading

1. Create a safe parser function in `scripts/utils.sh`:
```bash
function safe_load_env() {
    local envfile="${1:-${ENVFILE}}"
    while IFS='=' read -r key value; do
        [[ -z "${key}" || "${key}" =~ ^\[ || "${key}" =~ ^# ]] && continue
        # Trim whitespace and quotes
        key="${key// /}"
        value="${value#\"}"; value="${value%\"}"
        export "${key}=${value}"
    done < "${envfile}"
}
```

2. Replace both call sites in `utils.sh` and `lemper-cli.sh`.
3. Test with edge-case `.env` files (special characters, empty values).

---

## 9. Changelog Convention

Maintain a `CHANGELOG.md` following [Keep a Changelog](https://keepachangelog.com/) format:

```markdown
## [3.0.0] - 2026-XX-XX

### Added
- CrowdSec HIPS integration (scripts/install_crowdsec.sh)
- bats-core integration test suite (tests/integration/)
- `lemper-cli site list` subcommand

### Changed
- Minimum Bash version: 5.0+
- Default PHP version: 8.3
- SSL key size: 4096 bits (was 2048)

### Fixed
- `fial` typo in lemper-create.sh and lemper-db.sh
- `cgi.fix_pathinfo = 1` → `0` in all PHP-FPM pool configs
- Removed NOPASSWD:ALL sudo rule for lemper user

### Removed
- PHP 5.6–7.4 support (EOL versions)
- `apt-key` usage (replaced with signed-by keyrings)
- NAXSI WAF (legacy, replaced by ModSecurity v3)
```

---

## 10. Contact

For questions about this guide or the LEMPer project:

- **GitHub:** [joglomedia/LEMPer](https://github.com/joglomedia/LEMPer)
- **Issues:** [GitHub Issues](https://github.com/joglomedia/LEMPer/issues)
- **Maintainer:** Edi Septriyanto `@joglomedia`
