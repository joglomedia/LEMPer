# Module decomposition for v4

Roadmap 2.12 and 2.37 describe one architecture workstream, A4. Its accepted
scope is implemented: business logic lives in Bash core, runtime and service
modules, with compatible CLI and standalone entry points.

## Boundaries

| Layer | Responsibility | Examples |
|---|---|---|
| `lib/core/` | Shared primitives, allowed imports, contracts and code exports | `registry.sh`, `execution.sh`, `encryption.sh`, `deployment.sh` |
| `lib/runtime/` | Normalize requests, choose service operations and propagate status | `site/create.sh`, `site/manage.sh`, `stack/update.sh`, `components/lifecycle.sh` |
| `lib/services/` | Render configuration and implement component operations | `nginx/vhost.sh`, `php/pools.sh`, `site/skeletons.sh`, component install/remove drivers |
| `lib/compat/` | Prepare and isolate legacy execution context | Component, site and updater process adapters |
| `lib/lemper-*.sh`, `scripts/` | Preserve public filenames; initialize and dispatch | CLI plugin loaders, standalone lifecycle scripts, Nginx compatibility loaders |

Ordinary site provisioning now delegates vhost rendering, FPM pools and framework
setup to services. Site feature management delegates SSL, Nginx features and
protection. Updates delegate PHP patching/migration, Nginx repository/package
operations, MariaDB and tooling. Backup, benchmark, listing, permissions, account
creation and ModSecurity tuning also have runtime/service boundaries.

The creation runtime shrank from 1,686 to 217 lines. The manager and updater
plugins are now 58 and 60 lines respectively. These counts describe the
implementation snapshot, rather than a required size limit.

## Component contract

`lemper_component_driver ACTION COMPONENT` resolves an internal module name and
entry function from the registry. `lemper_component_apply` loads that allowed
module and forwards arguments without evaluating them as shell code. Aliases
resolve to the canonical driver while retaining requested backend selection.

Full-stack recipes and CLI component adapters use this contract. The 37 extracted
installer/remover/server scripts retain their filenames; eight Nginx scripts load
the corresponding service modules. Existing thin optional-service adapters and
older recorded checkouts keep their compatibility fallback.

Standalone lifecycle adapters handle help/version before loading private profiles.
They initialize configuration/helpers, validate the target environment and acquire
the shared operation lock. Sourced adapters rely on the enclosing operation's
initialization and lock. Build defaults and updater constants initialize through
explicit functions, rather than during module imports.

Internal functions retain some legacy request globals and Bash dynamic scope.
Legacy `run` and `fail` may terminate their installer/CLI child process; loading a
service module does not provide those helpers or a validated profile. Invoke
operations through their runtime/adapters. Function-only imports are safe to inspect,
but executing an installer still requires a designated disposable Linux environment
for tests, or an explicitly authorized target server.

## Extending the implementation

1. Add function-only service modules and a runtime use case when needed. Keep
   host initialization, configuration loading and dispatch out of imports.
2. Register lifecycle module/entry mappings in `lib/core/registry.sh` and allowed
   imports in `lib/core/execution.sh`. Preserve installer/remover wrappers and
   command exports; bootstrap and tooling refresh share the deployment contract.
3. Preserve validation, provisioning markers, configuration backups, dry-run
   guards and reload/recovery behavior. New mutations use `lemper_exec` and the
   shared operation lock; return recoverable failures.
4. Test behavior through public paths and isolated modules. Structural tests
   inspect the owning implementation; compatibility tests still load wrappers.

## Value and limits

This is worthwhile for v4 maintenance: a component change has one service owner,
imports can be tested without starting an installer, and CLI/full-stack paths
share dispatch. The clearer boundaries also reduce the amount of unrelated code
an agent or contributor needs to understand before a change.

The cost is more files and explicit loader/registry maintenance. This extraction
preserves existing behavior and compatibility, including legacy helper contracts;
it does not automatically improve package speed, eliminate all global state or
prove every provider/platform upgrade. Further state/API cleanup is optional work
that can be assessed separately.

## Verification

The added decomposition tests check import safety, matching adapter/registry
contracts, literal argument forwarding and failure propagation, updater shell
isolation, and help/version behavior without private configuration. Existing
application, backup, PHP, FTP, ownership, lifecycle and encryption regressions
remain part of the full Linux Bats suite.

Final verification results and native acceptance scope are recorded in
[ROADMAP_AUDIT.md](ROADMAP_AUDIT.md#a4-module-decomposition-follow-through--2026-11-23).
Exact clean-commit release assets, candidate CI and publication remain separate
gates in [RELEASE_V4.md](RELEASE_V4.md).
