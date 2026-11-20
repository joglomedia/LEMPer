# Architecture §4 and issue #92: alignment audit

Audit date: 2026-11-20. Scope: the current, uncommitted working tree on
`3.x.x`, [Architecture §4](ARCHITECTURE.md#4-target-architecture-v40-cli-alignment-implemented),
and [GitHub issue #92](https://github.com/joglomedia/LEMPer/issues/92).
The issue is open, last updated 2026-10-27, with no comments when retrieved
using `gh issue view 92 --repo joglomedia/LEMPer --json body,comments,state,updatedAt,url`.
The findings below describe the pre-alignment snapshot. Implementation status
is recorded at the end; current code references reflect the migration.

## Recommendation

Treat issue #92 as the public command contract and Architecture §4 as the
internal responsibility model. Define those contracts together, then migrate
one complete command lifecycle at a time into the proposed directories.

Keep Bash and the existing shared parser. Introduce a command registry, a
component registry, explicit request/context passing, and service interfaces.
This gives CLI, TUI, independent component operations, and full-stack installation
the same behavior. Directory moves follow the interfaces and acceptance tests.

The P1 work provides useful foundations, but it does not yet establish full
issue #92 parity. The bootstrap is an additional roadmap feature; issue #92
does not explicitly require it.

## Original verified gaps, in recommended priority order

| Priority | Requirement or architectural goal | Evidence at audit time | Recommended outcome |
|---|---|---|---|
| 1 | Positional site domain and new create flags | [create parser](../lib/lemper-create.sh) accepts legacy flags; [domain assignment](../lib/lemper-create.sh) comes from `--domain-name`; [operand handling](../lib/lemper-create.sh) does not convert a positional operand into the domain. | Normalize positional domain, `--type`, `--runtime`, `--runtime-user`, and `--install-skeleton` into one site request. Preserve legacy spellings. |
| 1 | Site aliases, action flags, and multiple domains | [site dispatcher](../lib/lemper-site.sh) accepts exactly one remove argument; `delete`, `--purge`, and direct `enable/disable` routing are absent. [manage parser](../lib/lemper-manage.sh) expects each action flag to carry its own domain and exits after the first action. | One site use case handles canonical and alias commands, a target list, and normalized feature actions. |
| 1 | Selected PHP update and EOL removal | [stack validation](../lib/lemper-stack.sh) restricts all operations to PHP 8.2–8.5. [PHP control](../lib/lemper-stack.sh) requires a version. [update delegation](../lib/lemper-stack.sh) drops `--php-version`. The [existing remover](../scripts/remove_php.sh) offers EOL 8.1. | Resolve versions per operation, forward the selected scope, and document versionless behavior. |
| 2 | Shared command/component definitions | [bootstrap plugin map](../get-lemper), [tool installer](../scripts/install_tools.sh), and [tool updater](../lib/lemper-update.sh) repeat mappings. [stack registry](../lib/lemper-stack.sh) and [full-stack orchestration](../lib/core/lemper-stacks.sh) maintain separate component lists. | One command registry and one component registry, reused by each entry point and installation path. |
| 2 | Modules that can be reused and composed | [loader](../lib/core/loader.sh) eagerly sources core, account, ACME, SSH, and CLI code. [CLI help](../lib/core/cli.sh) contains domain-specific commands. [failure/execution helpers](../lib/core/logging.sh) exit the caller; plugins self-dispatch when sourced. | Lazy loading, namespaced functions, explicit inputs and returned statuses; isolate legacy initialization/termination in adapters. |
| 3 | Coherent versioned code deployment | [bootstrap](../get-lemper) installs a versioned release, then [copies core/plugins](../get-lemper) into mutable `/etc/lemper` paths. | Select one immutable release tree atomically; retain old paths through compatibility adapters. |
| 3 | Accurate architecture status | [§4.4 diagram](ARCHITECTURE.md) says only `lemper-stacks.sh` is present, although core has 16 shell files; runtime/services still contain only directory markers. §4.2 and parts of §4.3 also describe older structure or proposals. | Separate observed implementation, remaining work, and proposed policy; update diagrams after each migrated lifecycle. |

The `lemperctl` executable alias already exists in the bootstrap, tools installer,
and tooling updater. Retaining `lemper-cli` is compatible with making `lemperctl`
the preferred name in help and documentation.

The current [stack tests](../tests/unit/stack_contracts.bats) explicitly expect
versionless PHP restart to fail. Passing those tests does not demonstrate the
versionless restart example requested in issue #92.

## Proposed responsibility boundaries

~~~text
bin/                          thin bootstrap; preferred lemperctl entry point
lib/core/                     parser, config/schema, logging, execution,
                              registries, locking and state primitives
lib/runtime/site/             site command adapter and create/update/remove use cases
lib/runtime/stack/            stack command adapter and lifecycle orchestration
lib/runtime/account/, db/     account and database use cases
lib/runtime/tui/              interactive adapter to the same use cases
lib/services/nginx/, php/     install/remove/update/control service drivers
lib/services/acme/, ...       certificate and remaining service drivers
lib/compat/                   legacy command, helper and installed-path adapters
scripts/                      existing entry points retained during migration
etc/, share/                  templates and assets
~~~

The core contains mechanisms shared across domains. Site policy, account policy,
certificate operations, and full-stack recipes belong in runtime/services.
Existing helpers can move gradually as their callers migrate.

~~~mermaid
flowchart TD
    CLI["lemperctl / lemper-cli"] --> ADAPTER["Command adapters"]
    TUI["TUI"] --> REQUEST["Normalized request"]
    ADAPTER --> REQUEST
    REQUEST --> USECASE["Site / stack / account / database use cases"]
    USECASE --> DRIVER["Nginx / PHP / ACME / other drivers"]
    DRIVER --> OS["Packages, files, databases, systemd"]
    CORE["Core: config, registry, execution, locks, state"] -.-> ADAPTER
    CORE -.-> USECASE
    CORE -.-> DRIVER
~~~

Use a common execution flow:

1. Parse and normalize aliases and options without loading private configuration.
2. Validate the request and resolve domains, installed instances, and capabilities.
3. Load only required drivers/configuration; perform privilege and dependency checks.
4. Build the operation plan, acquire locks for shared resources, and execute.
5. Validate resulting configuration, reload affected services, and report outcomes.

For performance, help/version should need neither root nor decryption. The current
[entry point](../bin/lemper-cli.sh) requests root before dispatch. Batch site
changes should collect affected service reloads and validate/apply them together
where practical. Measure process invocations and startup time before claiming
speed improvements.

### Module and registry contracts

- New sourced library files define functions without dispatching commands,
  changing shell options, setting traps, initializing the host, or exiting.
  An idempotent load guard is acceptable.
- Names such as `lemper_site_update` and `lemper_php_restart` make ownership clear.
  Use positional inputs or explicitly passed Bash arrays/context, with documented
  fields and returned statuses. Keep compatibility globals inside legacy adapters.
- A command registry declares canonical command paths, aliases, accepted options,
  help metadata, and handler identifiers. Bootstrap, install/update, and dispatch
  reuse its installation metadata during the transition.
- A component registry declares canonical IDs, aliases, drivers, capabilities,
  version resolvers, dependencies, and ownership keys. Drivers resolve actual
  packages and units; a package prefix alone does not establish ownership.
- Use static, validated Bash definitions and arrays. Do not introduce a new
  framework, custom configuration language, dynamic `eval`, or arbitrary handler paths.
- The execution context carries dry-run, config/state paths, target selection,
  locks and results. Every filesystem/database/service mutation must honor it,
  including redirections and cleanup.
- Isolate existing self-dispatching scripts in child processes until extracted.
  Preserve their statuses. Translate legacy syntax to the common request;
  avoid recursive calls between canonical and legacy commands.

Full-stack installation becomes a recipe over this same component registry,
including prerequisites and ordering. It should not maintain another installer list
or launch the public CLI once for each component.

## Public CLI and policy decisions

Examples below are proposed acceptance commands, not claims about current support.

~~~bash
lemperctl site create example.com --type=wordpress --runtime=php@8.5 \
  --runtime-user="$USER" --install-skeleton --webroot="$HOME/example.com"
lemperctl site update example.com second.example.com --ssl-enable --cors-enable
lemperctl site enable example.com
lemperctl site remove example.com --purge
lemperctl stack remove php --php-version 8.1
lemperctl stack update php --php-version 8.4
lemperctl stack restart php
~~~

Use `site create|update|remove` as canonical operations. Keep `add` → `create`,
`manage/mod` → `update`, and `delete` → `remove`. Direct `enable/disable`
becomes an update request with the corresponding action.

Accept feature-first flags from the issue, such as `--ssl-enable`, as well as
verb-first forms such as `--enable-ssl`. Both refer to the same action. Preserve
legacy `--enable-ssl DOMAIN` through an explicit compatibility parser; the new
form uses boolean action flags and separate positional domains. Reject ambiguous
mixed forms and contradictory actions before execution.

For creation, map `--type` to the existing framework/CMS choice,
`--runtime=php@VERSION` to runtime family/version, and `--runtime-user` to the
existing account model. Define skeleton behavior per site type: adding an alias
for `--install-app` alone does not prove that every application branch honors it.
Reject conflicting legacy/new values and unsupported runtime families.

### PHP selection

The issue's PHP 8.0/8.1 creation examples are historical. Do not reintroduce EOL
installation to match them. Distinguish the supported installation policy
(currently 8.2–8.5 in the source) from the installed inventory.

| Operation | Recommended selection policy |
|---|---|
| Install | Explicit supported version, or the configured supported default. |
| Remove | Explicit installed version, including EOL; auto-select only when one exists. Require selection or an explicit `--all-versions` when several exist. Check site references and per-version ownership before removal. |
| Update | Selected installed version when given; otherwise all installed versions. Apply supported updates and preserve/report the existing EOL remediation policy. Never silently migrate EOL sites. |
| Start/stop/restart/reload/status | Selected installed PHP-FPM version when given; otherwise all installed FPM versions, including EOL. Report the resolved versions and per-version outcomes. |

The versionless control default deliberately follows the issue's
`stack restart php` example. Explicit `--php-version` limits the scope;
`--all-versions` can make the default scope explicit. Detect installed FPM
instances separately from CLI-only PHP packages. Fail clearly if none exist.

The current [PHP updater](../lib/lemper-update.sh) discovers all branches and
handles known security patch/remediation state. A selected update must constrain
that discovery and execution; merely forwarding an option to a parser that does
not support it is insufficient. Specify whether ordinary package upgrades and
source rebuilds are also part of the driver update contract.

### Removal and batches

Recommend that `site remove` unregister the site while retaining application
data. `--purge` selects deletion of recorded, site-owned artifacts; `--yes`
is a separate proposed prompt-bypass option. Purge must not remove shared service
packages, accounts, PHP pools, certificates, databases, or directories without
ownership and reference checks. Preserve the existing owner-based webroot guard.
Older sites without reliable ownership metadata require an explicit reconciliation
step before automated data purge.

Validate all batch inputs and conflicts before mutation. Return a nonzero status
if any target fails and report successes/failures per target. Use deterministic
action ordering and restore configuration snapshots where feasible. State clearly
when shared reloads fail; database deletion and external certificate issuance
cannot be treated as a single reversible transaction.

## Incremental delivery order and acceptance gates

1. **Define the contract and tests.** Record canonical/legacy normalization,
   PHP selection, purge ownership, action conflicts, and status propagation.
   Reconcile §4.2–4.4 status text with the actual working tree.
2. **Introduce registries and the execution interface.** Initially point to
   existing adapters; retain current commands and installed paths. Verify command
   maps agree across bootstrap, installer, updater, CLI and TUI.
3. **Migrate PHP stack lifecycle.** Implement operation-specific version resolution,
   selected update, EOL removal and versionless FPM control. Extract PHP driver
   functions as this lifecycle becomes composable.
4. **Migrate site lifecycle.** Complete positional creation, aliases, batches,
   feature actions, metadata and purge semantics; delegate service work to drivers.
5. **Migrate remaining services and full-stack recipes.** Reuse capabilities,
   dependencies and ownership tracking; remove superseded lists and implementations.
6. **Consolidate deployment.** Use one versioned code tree selected through
   `/opt/lemper/current`, keeping configuration and state outside releases.
   Retain old paths as thin adapters. Code rollback does not roll back packages,
   database changes, or service configuration.

Acceptance coverage should exercise literal issue commands (substituting current
supported versions for new installations), aliases, options before/after domains,
multi-domain outcomes, selected PHP update, installed EOL removal, versionless
control, help without root/config, dry-run boundaries, and legacy compatibility.
Verify installer/bootstrap/updater exports and driver failure propagation.
Run system-changing lifecycle tests only in disposable Debian/Ubuntu environments.

This audit used source inspection and GitHub metadata. It did not run installers,
change services, or rerun the earlier implementation's runtime test suite.

## Implementation status (2026-11-20)

Issue #92 site/stack contracts now use runtime adapters: positional creation and
aliases, batches, ownership-based purge/adoption, operation-specific PHP selection,
versionless FPM control, selected security/package updates, and reference guards.

Commands, aliases, components and full-stack recipes share registries.
Bootstrap/full installation/tooling refresh share root-owned code snapshots and
an atomic release selector. Public help/version precedes root/config loading.
Config backup excludes release-code compatibility links.

Application/component internals remain behind adapters for gradual extraction;
account/database/TUI internals keep their original files. Native nftables is
outside this alignment. Configuration rollback does not reverse external
certificate issuance, database deletion, or package changes.

Validation completed in a disposable, unprivileged Ubuntu 24.04 container:
293 Bats tests passed, including 27 alignment contracts. ShellCheck 0.11.0
(with sourced-file analysis), Bashate, module syntax, workflow YAML and diff
whitespace checks passed. The project mount was read-only. Host installers and
live service/database deployment were not executed.
