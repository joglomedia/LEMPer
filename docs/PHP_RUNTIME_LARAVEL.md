# PHP runtime defaults and Laravel routing

This guide covers [issue #91](https://github.com/joglomedia/LEMPer/issues/91)
and [issue #170](https://github.com/joglomedia/LEMPer/issues/170).

## Choose the system PHP default

```bash
sudo lemperctl stack config php --default-runtime=php@8.4 --dry-run
sudo lemperctl stack config php --default-runtime=php@8.4
```

The command changes the registered `php` CLI alternative and matching installed
`phar`, `phar.phar`, `php-config`, and `phpize` alternatives. Developer tools that
are not installed for the selected version are reported and skipped. Every
available target is validated before any alternative changes. Missing or
unregistered PHP targets fail without changing the profile.

`DEFAULT_PHP_VERSION` is updated in the installed `/etc/lemper/lemper.conf`
profile. Existing credentials and unrelated settings are preserved, as is
profile encryption. Changes use the shared operation lock, a protected backup,
and atomic profile replacement. Failure restores the previous alternatives,
including their automatic/manual modes. Selecting the same version again does
not rewrite an unchanged profile.

The selected version becomes the default for **new** sites and subsequent
installation operations. Existing virtual hosts and FPM pools keep their
explicit versions; the command does not restart FPM or migrate a website.
Install the desired CLI/FPM packages before selecting a runtime. Current
supported defaults are PHP 8.2–8.5; the PHP 8.0 example in the original issue is
obsolete under the repository's current support policy. PHP removal and EOL
migration remain separate lifecycle operations.

Select a PHP version compatible with the application's Composer requirements;
repository support for a PHP release does not make every Laravel version
compatible with that release.

The PHP installer uses the same alternatives driver, avoiding a second set of
version-switching commands. CLI-only installations need not install PHP
compiler/development tools merely to select a CLI default.

## Laravel at the domain root

Prepare a Laravel project, configure its protected application environment,
and point the site at the **project directory**:

```bash
sudo lemperctl site create example.com --type laravel \
  --runtime php@8.4 --runtime-user lemper \
  --webroot /home/lemper/apps/example
```

The generated document root is `/home/lemper/apps/example/public`. New Laravel
vhosts execute only `public/index.php`; other PHP-looking files, including
versioned PHP extensions, PHTML, and PHAR files, are rejected. Framework and
private application files stay outside the public document root.

Routes with a trailing slash redirect to their canonical URL, unless they refer
to a real directory. Redirects use HTTP **308**, preserving request methods and
POST bodies. Query strings and URI encoding are preserved. Existing Laravel
vhosts continue to use their saved configuration; the shared Laravel routing
include is refreshed through the existing Nginx template installation path.
Review custom vhosts before migrating their PHP execution rules.

## Laravel under an existing domain

Use a managed parent site and an existing non-root FPM pool. Parent ownership
metadata must exist: create the parent with `site create`, or reconcile an
existing site with `site adopt` and its actual owner, document root, and runtime.
The application project must already exist and be owned by its runtime user.

```bash
sudo lemperctl site app add example.com --mount /demo --type laravel \
  --webroot /home/lemper/apps/demo --runtime php@8.4 --runtime-user lemper

sudo lemperctl site app add example.com --mount /shop \
  --webroot /home/lemper/apps/shop

sudo lemperctl site app list example.com
sudo lemperctl site app update example.com --mount /demo --runtime php@8.3
sudo lemperctl site app remove example.com --mount /shop --yes
```

Omitted runtime/user options inherit the parent site's recorded runtime and
owner. `update` preserves omitted settings from the application record. When
selecting another runtime/user, first provision its FPM pool; the command reads
existing pool configuration and never creates a Linux account or downloads a
framework. The standard distro `www-data` pool and LEMPer's per-user Unix socket
pools are supported.

Mounts use a single lowercase URL segment, such as `/demo` or `/shop`; nested
mount prefixes and reserved management paths are rejected. Multiple applications
can coexist on a domain, each with its own project and explicit FPM socket.
`/demo` redirects to `/demo/`, and application routes retain the `/demo` base URL
when passed to Laravel. Static files are served from the project's `public`
directory. Routing uses a fixed front-controller path and never exposes the
whole project through a document-root symlink.

The generated mount repeats shared access restrictions inside its prefix
location, which Nginx matches before the parent regex locations. Server-level
authentication, security headers, and other inherited policies remain in force.
Detected per-location authentication/access policies cause the adapter to
refuse the mount, preserving the protected site. Move shared protection to the
server level or integrate the mount's locations explicitly. Custom per-location
WAF/include rules also need review; arbitrary policies are not automatically
translated.
The adapter requires the known server-level root anchor and refuses incompatible
layouts rather than guessing an insertion point.

Adding/updating/removing a mount snapshots the parent vhost, its SSL/non-SSL
variants, the affected fragment, and application metadata. `nginx -t` runs before
reload; failure restores the prior configuration. Shared locking serializes
mutations, and `--dry-run` validates inputs without creating locks or files.
Removing a mount deletes only its routing configuration and ownership record.
Application files and databases are retained. A removed parent can still have
its retained application mounts cleaned up with `site app remove`.

## Ownership, recovery, and architecture

Mounted application metadata lives under `/etc/lemper/site-apps/<domain>/` and
Nginx fragments under `/etc/nginx/site-apps/<domain>/`. Both are included in the
existing configuration backup roots. Application data needs its own backup.
Parent-site purge refuses attached mounts and overlapping application trees.
PHP removal inspects mounted-app fragments as well as ordinary vhosts.

| Layer | Implementation |
|---|---|
| Stack configuration use case | `lib/runtime/stack/config.sh` |
| PHP alternatives driver | `lib/services/php/defaults.sh` |
| Protected profile replacement | `lib/core/config-update.sh` |
| App request validation and ownership | `lib/runtime/site/apps.sh` |
| Nginx rendering, hook installation, rollback | `lib/services/nginx/apps.sh` |
| Laravel routing templates | `etc/nginx/vhost/site_laravel.conf`, `app_laravel.conf` |

These modules define functions without source-time dispatch. Existing stack/site
entry adapters and the shared module loader provide their public interfaces.
The PHP default and an app's FPM runtime are independent: switching the system
CLI does not silently retarget existing applications.

## Verification and limits

On 2026-11-21, the full Linux Bats suite passed **358/358** checks. Focused
regression cases cover registered/missing alternatives, invalid/EOL defaults,
private encrypted-profile preservation, idempotency, dry runs, rollback of
alternatives and profile writes, app ownership, SSL-variant restoration,
protected parent policies, mount removal, and PHP/purge references.

A designated disposable Podman/systemd **Ubuntu 24.04, native aarch64**
environment passed **11 live acceptance checks** with real PHP 8.3/8.4 and
Laravel **13.43.0**. The checks verified system alternatives and encrypted
profile persistence, unchanged existing FPM configuration, a new site's default
runtime, root-domain and mounted Laravel requests, Laravel's `/demo` base URL,
query strings, encoded redirects, POST bodies, static files, directory URLs,
blocked PHP/source paths, application updates/removal, purge/reference guards,
and inherited server authentication. Detected sibling-location authentication
was refused. Project data remained present after mount removal.

Changed Bash passed syntax checks, ShellCheck with sourced-file analysis,
and repository Bashate rules. Workflow YAML parsed and local documentation
references and whitespace checks passed. The new runtime-routing CI job is
configured; it has not yet run on GitHub.

These checks do not establish compatibility with every Laravel release,
arbitrary custom Nginx locations/includes, non-Unix FPM transports, or nested
mount prefixes. HTTP routing was tested in the disposable environment; public
DNS/ACME issuance and a production-site migration were outside this validation.
Existing custom per-location security policies require explicit integration.
