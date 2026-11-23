# PHP application capabilities

`lemperctl site create DOMAIN --type=TYPE` creates an Nginx vhost and PHP-FPM
configuration. Application download/setup is a separate choice, enabled with
`--install-skeleton` (aliases: `--install-app`, `-i`). Install the selected PHP
runtime and the application's required extensions/tools first.
CodeIgniter's Composer path uses distribution archives and production dependencies
as the runtime user; development/test dependencies are omitted.

Release deployment uses Bash with curl, jq, GNU tar, unzip/zipinfo and sha256sum.
OJS also requires `libxml2-utils` (xmllint). The base installer supplies these
tools; existing hosts can install missing packages with `sudo apt-get install jq
unzip libxml2-utils`. LEMPer's release helpers do not require Python.

| Capability | Types | Installation flag |
|---|---|---|
| Automatic skeleton path | `wordpress`, `wordpress-ms`, `woocommerce`, `laravel`, `lumen`, `symfony`, `codeigniter`, `drupal`, `owncloud`, `phalcon`, `phalcon-cli`, `phalcon-micro`, `phalcon-modules` | Available; downloads or generates project files using existing installers |
| Complete GitHub release deployment | `mautic`, `roundcube`, `snappymail`, `nextcloud`, `mybb` | Latest stable production package with published SHA-256 verification |
| Prepared source deployment | `phplist`, `slim` | Latest GitHub release archive plus production Composer dependencies |
| PKP production deployment | `ojs` | Latest stable production package from PKP's version manifest |
| Licensed manual deployment | `sendy`, `xenforo` | Installation flags rejected; supply your own licensed files |
| Vanilla PHP | `default` | Rejected; no application skeleton |

The CLI, legacy creation adapter and TUI use the same
[catalog](../lib/core/registry.sh) and
[capability driver](../lib/services/site/applications.sh). The TUI retains its
existing application choices and asks about installation only for automatic
types. `lemperctl site create --help` lists current capabilities without root.

```bash
sudo lemperctl account webowner
sudo lemperctl site create app.example.com --type=codeigniter --runtime=php@8.4 \
  --runtime-user=webowner --install-skeleton

sudo lemperctl site create mail.example.com --type=roundcube --runtime=php@8.4 \
  --runtime-user=webowner --install-skeleton
sudo lemperctl site create marketing.example.com --type=mautic --runtime=php@8.4 \
  --runtime-user=webowner --install-skeleton
```

For manual deployment, omit the installation flag, deploy files as the runtime user, choose a document root
appropriate to that application release, and follow its upstream database,
configuration, scheduled-job and setup instructions. LEMPer's generated
placeholder is not the application. Sendy and XenForo deployment require your own licensed
artifacts; LEMPer does not download or provide them. Roundcube and SnappyMail are webmail clients;
incoming/outgoing mail services are managed separately with
[`lemperctl mail`](MAIL.md).

## Mautic and Roundcube complete releases

The [release driver](../lib/services/site/releases.sh) queries GitHub's
`releases/latest` API for [Mautic](https://github.com/mautic/mautic/releases/latest)
and [Roundcube](https://github.com/roundcube/roundcubemail/releases/latest) at each
new installation. It validates stable-release metadata and selects Mautic's full
version ZIP or Roundcube's `-complete.tar.gz` from that response. Versions and
checksums are resolved dynamically; the installer has no fixed version pins.
The selected asset's published SHA-256 digest is required and checked before
extraction. Missing metadata/assets/digests, prereleases and download errors fail
installation without a fallback to an older version.

The metadata is resolved once per deployment so a concurrent upstream release
cannot change the selected package midway. API access is unauthenticated and
subject to GitHub's rate limits; rate-limit failures remain failures. Dry runs
perform no release lookup or downloads. The receipt records the actual installed
version and checksum. Packages include dependencies and built assets;
installation does not run Composer or JavaScript builds.

Choose a LEMPer PHP 8.2–8.5 runtime supported by the selected upstream release.
Its bundled platform check must pass before publication; an incompatible latest
release fails installation rather than selecting an older one.
Prerequisite checks run before site
mutations and report missing extensions. The normal PHP installer includes the
required extension packages where available; a partial PHP installation may
need reconciliation first. Mautic requires its MySQL PDO driver and extensions
including IMAP, intl, GD and ZIP. Roundcube requires a PDO database driver, intl,
mbstring, DOM and sockets. Enable required extensions in both CLI and FPM.

Use a dedicated, empty project directory under `/home/USER/webapps/`, `/srv/`,
`/var/www/` or `/opt/`. Existing files are retained and installation is refused
unless the directory contains a valid LEMPer receipt for that application and valid project
markers. A repeated driver call preserves its installed version and configuration
without a network lookup; it does not overwrite files or perform an upgrade.
Existing vhosts still require the normal site
management commands rather than another `site create`.

Mautic's document root is the extracted package root. Roundcube 1.7 uses
`PROJECT/public_html`, keeping configuration, logs, temporary files and code
outside the served directory. The vhost permits only Mautic's `index.php` or
Roundcube's `index.php`, `static.php` and protected `installer.php`; other PHP
requests and private directory requests are denied. Configuration/cache
directories and the release receipt retain private permissions.

This command installs **complete application files and the vhost**. Finish
database, administrator, SMTP/IMAP and scheduled-job setup using the upstream
installer. No database/account is invented or recorded as owned during skeleton
deployment. Use [Mautic's installation guide](https://docs.mautic.org/en/7.2/getting_started/how_to_install_mautic.html)
and [Roundcube's installation guide](https://github.com/roundcube/roundcubemail/wiki/Installation).
Mautic's Composer marketplace/upgrade workflow remains an upstream-managed choice.

Setup endpoints (`/installer` for Mautic, `/installer.php` for Roundcube) allow
loopback access only. To reach them remotely, use an SSH tunnel with the app's
correct Host header:

```bash
ssh -N -L 127.0.0.1:8080:127.0.0.1:80 ADMIN@SERVER
# In another terminal, verify the setup page through the tunnel:
curl -H 'Host: mail.example.com' http://127.0.0.1:8080/installer.php
```

For browser setup, arrange the same domain/Host mapping through the tunnel.
Use HTTPS for normal application access and disable/remove Roundcube's installer
after configuration as upstream recommends. LEMPer preserves TLS certificate
validation for mail connections; configure an endpoint covered by its certificate.

Roundcube ownership records identify the served `public_html` directory. Site
removal retains application data by default; `--purge` removes the recorded
document root and leaves the project's private siblings for deliberate cleanup.

Automatic paths must produce nonempty application markers (for example,
CodeIgniter's `spark` and `public/index.php`, or WordPress's
`wp-includes/class-wp.php` and `index.php`) before success and ownership recording.
Missing files return failure, including when a legacy installer returned zero.
Partial files/configuration can remain after an installer failure; inspect them
before retrying. This check establishes the project-file contract, not completed
database setup, dependency installation or application health. Existing installer
behavior and upstream release compatibility still apply.

The A3 acceptance suite exercises rejection before mutations, manual vhosts
through real PHP-FPM, complete Mautic/Roundcube packages and their setup routes,
and a CodeIgniter skeleton with HTTP validation. Unattended database/admin/mail
configuration and Sendy's licensed-artifact interface remain outside this scope.
Other automatic application paths are retained; this change does not claim new
live deployment validation for each of them.

## Additional applications

All applications use the shared CLI/TUI catalog. The installed command still
uses `--install-skeleton` (aliases: `--install-app`, `-i`); without the flag,
application-specific vhost setup remains available for manually deployed files.
PHP executes through the chosen runtime user's Unix FPM socket. Automatic setup
requires a non-root account, an empty dedicated project directory and the selected
runtime's required extensions. Composer and Git are also required for phpList
and Slim. Existing projects and configuration are preserved on repeated installs.

| Type | Package source | Document root | Configuration and routing |
|---|---|---|---|
| `snappymail` | Latest normal standalone asset from `the-djmaze/snappymail`; excludes cPanel/Nextcloud variants | Project root | Executes `index.php`; protects `data/` and application internals |
| `nextcloud` | Latest `nextcloud/server` release, then its matching production asset in `nextcloud-releases/server` | Project root | Official front-controller exceptions, DAV/OCS paths, `.well-known`, static assets and Unix-socket PHP |
| `mybb` | Latest MyBB 1.8 full `mybb_*.zip`; extracts `Upload/` | Project root | Public PHP allowlist, protected `inc/`, loopback installer and MyBB friendly URLs |
| `phplist` | GitHub's latest phpList release source archive, then Composer production installation | `PROJECT/public_html/lists` | Issue #66; public endpoint allowlist, protected configuration and loopback administration |
| `xenforo` | Your licensed installation files; no automatic download | Project root | Issue #149; friendly URLs, protected `src/`, `internal_data/`, installer data and Unix-socket PHP |
| `ojs` | PKP's stable production manifest/package | Project root | Issue #35; preserved `PATH_INFO`, public assets and private submission storage |
| `slim` | Latest official Slim skeleton release plus compatible Slim 4 dependencies from Composer | `PROJECT/public` | Only the public front controller executes; source/vendor/logs stay outside the document root |

```bash
sudo lemperctl account webowner
sudo lemperctl site create webmail.example.com --type=snappymail --runtime=php@8.3 --runtime-user=webowner --install-skeleton
sudo lemperctl site create cloud.example.com --type=nextcloud --runtime=php@8.3 --runtime-user=webowner --install-skeleton
sudo lemperctl site create forum.example.com --type=mybb --runtime=php@8.3 --runtime-user=webowner --install-skeleton
sudo lemperctl site create lists.example.com --type=phplist --runtime=php@8.3 --runtime-user=webowner --install-skeleton
sudo lemperctl site create journal.example.com --type=ojs --runtime=php@8.3 --runtime-user=webowner --install-skeleton
sudo lemperctl site create api.example.com --type=slim --runtime=php@8.3 --runtime-user=webowner --install-skeleton
# Deploy your licensed XenForo files separately, then configure its vhost.
sudo lemperctl site create community.example.com --type=xenforo --runtime=php@8.3 --runtime-user=webowner
```

Nextcloud's source repository may name a newer release than the distribution
repository's `latest` endpoint. LEMPer resolves the exact matching distribution
tag and verifies its published digest, rather than installing an older package.
Validated internal license-file aliases are copied as regular files in one
extraction pass; links cannot escape the package and filesystem symlinks are not
created. The configuration follows the upstream root-install Nginx guidance and
does not use a TCP PHP backend or enable FastCGI caching.

phpList, Slim's skeleton and PKP's OJS manifest currently provide no published
GitHub asset SHA-256 digest for these archives. Their downloads use verified
HTTPS from the constrained official release URL; the computed archive hash is
recorded for provenance. `.lemper-integrity` distinguishes `verified-https` from
`published-sha256`. Existing SHA-256 requirements for the complete GitHub assets
remain enforced. phpList explicitly uses the GitHub release file instead of
SourceForge. Composer installs its UI/language/plugin dependencies as the runtime
user; it never executes package scripts as root.

OJS's production package includes a default configuration. LEMPer prepares that
staged default with the actual domain and `files_dir = "PROJECT-files"`, creates
that sibling directory with mode 0700, and keeps `installed = Off` until you
complete the upstream installer. Private submissions stay outside the document
root; `public/` holds deliberately public files. If you enable HTTPS later,
update OJS's `base_url` to match. Customize database, administrator and mail
settings through the upstream setup process; LEMPer does not invent or own them.

Use an SSH tunnel with the correct Host header for MyBB's `/install/index.php`,
OJS's `/index.php/index/install`, phpList's `/admin/index.php` and XenForo's
`/install/` setup. Nextcloud remains loopback-only while its empty
`.lemper-setup-pending` marker exists, including after it creates `config.php`.
After completing configuration and enabling HTTPS, publish it deliberately:

```bash
# Run on the target server after completing Nextcloud setup.
sudo unlink /home/webowner/webapps/cloud.example.com/.lemper-setup-pending
```

The marker is non-secret and readable by Nginx; credentials and application data
remain private. SnappyMail generates its own administrator credential in the
protected data directory; follow its installation guide to retrieve and change
it. Configure IMAP/SMTP endpoints with valid certificates. Slim's receipt records
the skeleton version; `composer show slim/slim` shows the installed framework.

These commands deploy files, dependencies and routing. They do not replace
upstream database installation, mail configuration, cron scheduling, journal
setup or licensed application setup. For projects whose document root is a
subdirectory, `--purge` removes the recorded document root; private siblings and
OJS submission storage require deliberate, backed-up cleanup.
