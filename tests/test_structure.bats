#!/usr/bin/env bats
##
# Bats test suite for LEMPer architecture structure.
#
# These tests verify that the refactoring (Phase 2 Task 11) was done correctly:
# - install.sh and remove.sh are thin wrappers
# - lemper.sh sources shared lemper_stacks.sh instead of inline functions
# - lemper_stacks.sh contains the shared lemper_install() and lemper_remove()
#

setup() {
    export BASE_DIR="${BATS_TEST_DIRNAME}/.."
}

# Assert that grep finds no match. Unlike "! grep", this fails the test reliably.
refute_grep() {
    run grep "$@"
    [ "${status}" -ne 0 ]
}

@test "install.sh is a thin wrapper that sources lemper_stacks.sh" {
    # install.sh should NOT contain inline lemper_install function body
    local inline_count
    inline_count=$(grep -c 'function lemper_install()' "${BASE_DIR}/install.sh" 2>/dev/null || true)
    [ "${inline_count}" -eq 0 ]

    # install.sh should source lemper-stacks.sh from lib/core/
    grep -q 'lib/core/lemper-stacks.sh' "${BASE_DIR}/install.sh"

    # install.sh should call lemper_install
    grep -q 'lemper_install' "${BASE_DIR}/install.sh"
}

@test "install.sh calls requires_root and preflight before install" {
    grep -q 'requires_root' "${BASE_DIR}/install.sh"
    grep -q 'preflight_system_check' "${BASE_DIR}/install.sh"
    grep -q 'header_msg' "${BASE_DIR}/install.sh"
    grep -q 'footer_msg' "${BASE_DIR}/install.sh"
}

@test "remove.sh is a thin wrapper that sources lemper_stacks.sh" {
    # remove.sh should NOT contain inline lemper_remove function body
    local inline_count
    inline_count=$(grep -c 'function lemper_remove()' "${BASE_DIR}/remove.sh" 2>/dev/null || true)
    [ "${inline_count}" -eq 0 ]

    # remove.sh should source lemper-stacks.sh from lib/core/
    grep -q 'lib/core/lemper-stacks.sh' "${BASE_DIR}/remove.sh"

    # remove.sh should call lemper_remove
    grep -q 'lemper_remove' "${BASE_DIR}/remove.sh"
}

@test "remove.sh calls requires_root and preflight before remove" {
    grep -q 'requires_root' "${BASE_DIR}/remove.sh"
    grep -q 'preflight_system_check' "${BASE_DIR}/remove.sh"
    grep -q 'header_msg' "${BASE_DIR}/remove.sh"
    grep -q 'footer_msg' "${BASE_DIR}/remove.sh"
}

@test "lemper.sh sources lemper_stacks.sh instead of inline functions" {
    # lemper.sh should NOT contain inline lemper_install or lemper_remove
    local install_count remove_count
    install_count=$(grep -c 'function lemper_install()' "${BASE_DIR}/lemper.sh" 2>/dev/null || true)
    remove_count=$(grep -c 'function lemper_remove()' "${BASE_DIR}/lemper.sh" 2>/dev/null || true)
    [ "${install_count}" -eq 0 ]
    [ "${remove_count}" -eq 0 ]

    # lemper.sh should source lemper_stacks.sh from lib/core/
    grep -q 'lib/core/lemper-stacks.sh' "${BASE_DIR}/lemper.sh"
}

@test "lemper_stacks.sh contains lemper_install function" {
    grep -q 'function lemper_install()' "${BASE_DIR}/lib/core/lemper-stacks.sh"
}

@test "lemper_stacks.sh contains lemper_remove function" {
    grep -q 'function lemper_remove()' "${BASE_DIR}/lib/core/lemper-stacks.sh"
}

@test "lemper.sh preserves CLI argument parsing (init_lemper_install)" {
    grep -q 'init_lemper_install' "${BASE_DIR}/lemper.sh"
}

@test "lemper.sh preserves getopt-based CLI flags" {
    grep -q 'getopt' "${BASE_DIR}/lemper.sh"
    grep -q 'install' "${BASE_DIR}/lemper.sh"
    grep -q 'remove' "${BASE_DIR}/lemper.sh"
}

@test "lemper.sh --help works without sudo or a dotenv file" {
    run env -u BASE_DIR bash "${BASE_DIR}/lemper.sh" --help
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Usage:"* ]]
    [[ "${output}" == *"install"* ]]
}

@test "lemper.sh runs from its checkout instead of cloning a nested copy" {
    local cli="${BASE_DIR}/lemper.sh"

    grep -qF 'LEMPER_ROOT=' "${cli}"
    grep -qF 'export BASE_DIR="${LEMPER_ROOT}"' "${cli}"
    refute_grep -q 'git_clone_lemper' "${cli}"
    refute_grep -qF 'git clone https://github.com/joglomedia/LEMPer.git' "${cli}"
}

@test "BASE_DIR and the dotenv resolve from the module location" {
    local stacks="${BASE_DIR}/lib/core/lemper-stacks.sh"
    local utils="${BASE_DIR}/scripts/utils.sh"

    grep -qF 'dirname "${BASH_SOURCE[0]}" )/../..' "${stacks}"
    refute_grep -qF 'BASH_SOURCE[1]' "${stacks}"

    # The dotenv lookup must not rewrite a guessed path with sed.
    refute_grep -qF "s|\\/scripts" "${utils}"
    grep -qF 'SCRIPTS_DIR}/..' "${utils}"
}

@test "utils.sh loads .env from the repository root regardless of CWD" {
    local tmp="${BATS_TEST_TMPDIR}/lemper-env"
    mkdir -p "${tmp}/scripts"
    cp "${BASE_DIR}/scripts/utils.sh" "${tmp}/scripts/utils.sh"
    printf 'LEMPER_DOTENV_PROBE="ok"\n' > "${tmp}/.env"

    run env -u BASE_DIR bash -c 'cd / && . "$1/scripts/utils.sh" && printf "%s" "$LEMPER_DOTENV_PROBE"' _ "${tmp}"
    [ "${output}" = "ok" ]
}

@test "lemper-stacks.sh wires in Bun.js install/remove" {
    grep -q 'install_bun.sh' "${BASE_DIR}/lib/core/lemper-stacks.sh"
    grep -q 'remove_bun.sh' "${BASE_DIR}/lib/core/lemper-stacks.sh"
}

@test "site-list plugin has validate_fqdn function" {
    grep -q 'function validate_fqdn' "${BASE_DIR}/lib/lemper-site-list.sh"
}

@test "install_redis.sh supports Valkey backend" {
    local redis="${BASE_DIR}/scripts/install_redis.sh"
    grep -q 'add_valkey_repo' "${redis}"
    grep -q 'REDIS_BACKEND' "${redis}"
    grep -q 'apt-cache show valkey-server' "${redis}"
    grep -q 'bookworm-backports' "${redis}"
}

@test "Valkey install preserves the packaged config and paths" {
    local redis="${BASE_DIR}/scripts/install_redis.sh"
    grep -q 'if \[\[ ! -f "${VALKEY_CONF}" \]\]' "${redis}"
    grep -q '/var/lib/valkey' "${redis}"
}

@test "Nginx DH params use a predefined RFC 7919 group" {
    local post_install="${BASE_DIR}/scripts/nginx/nginx_post_install.sh"
    grep -q 'DH_PARAM_GROUP' "${post_install}"
    grep -q 'genpkey -genparam' "${post_install}"
    refute_grep -q 'openssl dhparam -out' "${post_install}"
}

@test "Nginx repo installer is defined once and installs module packages" {
    local repo="${BASE_DIR}/scripts/nginx/nginx_repo.sh"
    local build="${BASE_DIR}/scripts/nginx/nginx_build.sh"
    refute_grep -q '^function install_nginx_from_repo' "${build}"
    grep -q 'EXTRA_MODULE_PKGS\[@\]' "${repo}"
}

@test "Nginx stream config is gated on module availability" {
    local post_install="${BASE_DIR}/scripts/nginx/nginx_post_install.sh"
    grep -q 'STREAM_AVAILABLE' "${post_install}"
    grep -q 'ngx_stream_module' "${post_install}"
}

@test "CLI resolves the config key file before LEMPER_PASSWORD" {
    local cli="${BASE_DIR}/bin/lemper-cli.sh"
    local key_line pass_line
    key_line=$(grep -n '/etc/lemper/.config_key' "${cli}" | head -1 | cut -d: -f1)
    pass_line=$(grep -n 'if \[\[ -n "${LEMPER_PASSWORD}" \]\]' "${cli}" | head -1 | cut -d: -f1)
    [ -n "${key_line}" ] && [ -n "${pass_line}" ] && [ "${key_line}" -lt "${pass_line}" ]
}

@test "valkey-server.service template exists" {
    [ -f "${BASE_DIR}/etc/systemd/valkey-server.service" ]
}

@test ".env.dist has REDIS_BACKEND and BUNJS config" {
    grep -q 'REDIS_BACKEND' "${BASE_DIR}/.env.dist"
    grep -q 'INSTALL_BUNJS' "${BASE_DIR}/.env.dist"
    grep -q 'BUNJS_VERSION' "${BASE_DIR}/.env.dist"
}

@test "site-list plugin exists and has list_vhosts function" {
    [ -f "${BASE_DIR}/lib/lemper-site-list.sh" ]
    grep -q 'function list_vhosts' "${BASE_DIR}/lib/lemper-site-list.sh"
}

@test "site-show plugin exists and has show_vhost_config function" {
    [ -f "${BASE_DIR}/lib/lemper-site-show.sh" ]
    grep -q 'function show_vhost_config' "${BASE_DIR}/lib/lemper-site-show.sh"
}

@test "install_tools.sh wires site-list and site-show plugins" {
    grep -q 'lemper-site-list' "${BASE_DIR}/scripts/install_tools.sh"
    grep -q 'lemper-site-show' "${BASE_DIR}/scripts/install_tools.sh"
}

@test "bunjs install and remove scripts exist" {
    [ -f "${BASE_DIR}/scripts/install_bun.sh" ]
    [ -f "${BASE_DIR}/scripts/remove_bun.sh" ]
}

@test "lemper-cli.sh help lists tui command" {
    grep -q 'tui' "${BASE_DIR}/bin/lemper-cli.sh"
}

@test "lemper-tui.sh provides interactive dashboard" {
    [ -f "${BASE_DIR}/lib/lemper-tui.sh" ]
    grep -q 'function init_lemper_tui' "${BASE_DIR}/lib/lemper-tui.sh"
    grep -q 'tui_menu' "${BASE_DIR}/lib/lemper-tui.sh"
    grep -q 'tui_system_status' "${BASE_DIR}/lib/lemper-tui.sh"
}

@test "lemper-db.sh has backup, restore, backup-schedule commands" {
    grep -q 'function cmd_backup' "${BASE_DIR}/lib/lemper-db.sh"
    grep -q 'function cmd_restore' "${BASE_DIR}/lib/lemper-db.sh"
    grep -q 'function cmd_backup_schedule' "${BASE_DIR}/lib/lemper-db.sh"
}

@test "lemper-db.sh help documents backup and restore subcommands" {
    grep -q 'backup' "${BASE_DIR}/lib/lemper-db.sh"
    grep -q 'restore' "${BASE_DIR}/lib/lemper-db.sh"
}

@test "database passwords are not passed as mysql CLI arguments" {
    grep -q 'MYSQL_PWD=' "${BASE_DIR}/lib/lemper-db.sh"
    refute_grep -rqE '(mariadb|mysql|mysqldump)[^|]*(-p"|--password=)' "${BASE_DIR}/lib" "${BASE_DIR}/scripts"
}

@test "scheduled database backups keep passwords out of crontab" {
    grep -q -- '--dbpass-file=' "${BASE_DIR}/lib/lemper-db.sh"
    refute_grep -q 'CRON_CMD=.*--dbpass=' "${BASE_DIR}/lib/lemper-db.sh"
}

@test "installer supplies app database password via environment" {
    grep -q 'LEMPER_DB_PASSWORD=' "${BASE_DIR}/lib/lemper-create.sh"
    refute_grep -q 'db account create.*--dbpass=' "${BASE_DIR}/lib/lemper-create.sh"
}

@test "install_crowdsec.sh and remove_crowdsec.sh exist" {
    [ -f "${BASE_DIR}/scripts/install_crowdsec.sh" ]
    [ -f "${BASE_DIR}/scripts/remove_crowdsec.sh" ]
}

@test "lemper-stacks.sh wires in CrowdSec install/remove" {
    grep -q 'install_crowdsec.sh' "${BASE_DIR}/lib/core/lemper-stacks.sh"
    grep -q 'remove_crowdsec.sh' "${BASE_DIR}/lib/core/lemper-stacks.sh"
}

@test "CrowdSec install includes WordPress web app scenarios" {
    # The official hub collection replaces the old local scenario files, which
    # were not valid CrowdSec scenarios and made `cscli hub install` fail.
    grep -q 'install_crowdsec_webapp_support' "${BASE_DIR}/scripts/install_crowdsec.sh"
    grep -q 'crowdsecurity/wordpress' "${BASE_DIR}/scripts/install_crowdsec.sh"
    grep -q 'crowdsecurity/base-http-scenarios' "${BASE_DIR}/scripts/install_crowdsec.sh"
    refute_grep -q 'wordpress-xmlrpc.yaml' "${BASE_DIR}/scripts/install_crowdsec.sh"
    refute_grep -q 'wordpress-bruteforce.yaml' "${BASE_DIR}/scripts/install_crowdsec.sh"
}

@test ".env.dist has CrowdSec WordPress config" {
    grep -q 'INSTALL_CROWDSEC_WORDPRESS' "${BASE_DIR}/.env.dist"
    grep -q 'INSTALL_CROWDSEC_PHPAPPS' "${BASE_DIR}/.env.dist"
}

@test "install_certbotle.sh supports DNS-01 wildcard certificates" {
    grep -q 'ACME_DNS_PROVIDER' "${BASE_DIR}/scripts/install_certbotle.sh"
    grep -q 'dns-01' "${BASE_DIR}/scripts/install_certbotle.sh" || \
    grep -q 'DNS-01' "${BASE_DIR}/scripts/install_certbotle.sh"
    grep -q 'request_wildcard_certificate' "${BASE_DIR}/scripts/install_certbotle.sh"
}

@test "install_certbotle.sh integrates with systemd-resolved" {
    grep -q 'function flush_dns_cache' "${BASE_DIR}/scripts/install_certbotle.sh"
    grep -q 'resolvectl flush-caches' "${BASE_DIR}/scripts/install_certbotle.sh"
    grep -q 'renewal-hooks/deploy' "${BASE_DIR}/scripts/install_certbotle.sh"
}

@test "TUI provides live log streaming and site creation wizard" {
    grep -q 'function tui_logs' "${BASE_DIR}/lib/lemper-tui.sh"
    grep -q 'function tui_follow_log' "${BASE_DIR}/lib/lemper-tui.sh"
    grep -q 'function tui_site_create_wizard' "${BASE_DIR}/lib/lemper-tui.sh"
}

@test "modsec plugin provides auto-tuning" {
    [ -f "${BASE_DIR}/lib/lemper-modsec.sh" ]
    grep -q 'function modsec_report' "${BASE_DIR}/lib/lemper-modsec.sh"
    grep -q -- '--auto' "${BASE_DIR}/lib/lemper-modsec.sh"
    grep -q 'lemper-modsec' "${BASE_DIR}/scripts/install_tools.sh"
}

@test "install_modsec.sh generates tuning config without placeholders" {
    grep -q 'lemper-tuning.conf' "${BASE_DIR}/scripts/install_modsec.sh"
    grep -q 'MODSEC_PARANOIA_LEVEL' "${BASE_DIR}/scripts/install_modsec.sh"
    refute_grep -q '{@SEC_BODY_LIMIT}' "${BASE_DIR}/scripts/install_modsec.sh"
}

@test "install_modsec.sh and remove_modsec.sh exist" {
    [ -f "${BASE_DIR}/scripts/install_modsec.sh" ]
    [ -f "${BASE_DIR}/scripts/remove_modsec.sh" ]
}

@test "ModSecurity uses the packaged nginx connector and CRS layout" {
    local install="${BASE_DIR}/scripts/install_modsec.sh"
    local remove="${BASE_DIR}/scripts/remove_modsec.sh"
    local modsec="${BASE_DIR}/lib/lemper-modsec.sh"

    grep -qF 'libnginx-mod-http-modsecurity' "${install}"
    grep -qF 'modsecurity-crs' "${install}"
    refute_grep -qE '(^|[[:space:]])nginx-mod-http-modsecurity([[:space:]]|$)' "${install}"

    # The connector is enabled by the package via modules-available.
    grep -qF '/usr/share/nginx/modules-available/mod-http-modsecurity.conf' "${install}"
    grep -qF '/etc/nginx/modules-enabled/50-mod-http-modsecurity.conf' "${install}"
    refute_grep -q '/usr/share/modsecurity/modsecurity.conf' "${install}"

    # CRS lives under /etc/modsecurity/crs and ships a setup template.
    grep -qF '/etc/modsecurity/crs/rules/*.conf' "${install}"
    grep -qF 'crs-setup.conf.example' "${install}"
    refute_grep -q 'git clone' "${install}"
    refute_grep -q 'MODSEC_CRS_VERSION' "${BASE_DIR}/.env.dist"

    # The CLI reads the packaged CRS location and reports its version.
    grep -qF '/etc/modsecurity/crs' "${modsec}"
    grep -qF 'modsecurity-crs' "${modsec}"

    # Removal uses the real package names and edits sites-available.
    grep -qF 'libnginx-mod-http-modsecurity' "${remove}"
    grep -qF 'sites-available' "${remove}"
    refute_grep -q 'sites-enabled/\*' "${remove}"
}

@test "lemper-stacks.sh wires in ModSecurity install/remove" {
    grep -q 'install_modsec.sh' "${BASE_DIR}/lib/core/lemper-stacks.sh"
    grep -q 'remove_modsec.sh' "${BASE_DIR}/lib/core/lemper-stacks.sh"
}

@test "ModSecurity nginx include and OWASP CRS config exist" {
    [ -f "${BASE_DIR}/etc/nginx/includes/modsec.conf" ]
    grep -q 'modsecurity' "${BASE_DIR}/scripts/install_modsec.sh"
    grep -q 'crs-setup.conf' "${BASE_DIR}/scripts/install_modsec.sh"
}

@test "lemper-encrypt.sh provides config encryption utilities" {
    [ -f "${BASE_DIR}/lib/lemper-encrypt.sh" ]
    grep -q 'function is_config_encrypted' "${BASE_DIR}/lib/lemper-encrypt.sh"
    grep -q 'function decrypt_config' "${BASE_DIR}/lib/lemper-encrypt.sh"
    grep -q 'function encrypt_config' "${BASE_DIR}/lib/lemper-encrypt.sh"
    grep -q 'function resolve_config_password' "${BASE_DIR}/lib/lemper-encrypt.sh"
    grep -q 'aes-256-cbc' "${BASE_DIR}/lib/lemper-encrypt.sh"
}

@test "bin/lemper-cli.sh supports --password flag for encrypted config" {
    grep -q 'LEMPER_CONFIG_PASSWORD' "${BASE_DIR}/bin/lemper-cli.sh"
    grep -q 'decrypt_config' "${BASE_DIR}/bin/lemper-cli.sh"
    grep -q 'ENCRYPT_CONFIG_AT_REST' "${BASE_DIR}/bin/lemper-cli.sh"
}

@test ".env.dist has ENCRYPT_CONFIG_AT_REST config" {
    grep -q 'ENCRYPT_CONFIG_AT_REST' "${BASE_DIR}/.env.dist"
    grep -q 'LEMPER_CONFIG_PASSWORD' "${BASE_DIR}/.env.dist"
}

@test "CI workflow targets Ubuntu 24.04" {
    grep -q 'ubuntu-24.04' "${BASE_DIR}/.github/workflows/main.yml"
}

@test "CI workflow uses ShellCheck v0.11.0" {
    grep -q 'shellcheck-v0.11.0' "${BASE_DIR}/.github/workflows/main.yml"
}

@test "CI workflow installs and verifies both FTP servers" {
    local workflow="${BASE_DIR}/.github/workflows/main.yml"

    grep -q 'name: Verify FTP server installation' "${workflow}"
    grep -q 'ftp-source:' "${workflow}"
    grep -q 'FTP_SERVER_INSTALLER="source"' "${workflow}"
    grep -q 'scripts/install_pureftpd.sh' "${workflow}"
    grep -q 'scripts/install_vsftpd.sh' "${workflow}"
}

@test "Podman test script defaults to Ubuntu 24.04" {
    grep -q 'ubuntu:24.04' "${BASE_DIR}/scripts/test_podman.sh"
}

@test "Nginx PageSpeed module and config are fully removed" {
    refute_grep -rqiE 'page.?speed|ngx_pagespeed' \
        "${BASE_DIR}/scripts" "${BASE_DIR}/etc" "${BASE_DIR}/lib" \
        "${BASE_DIR}/bin" "${BASE_DIR}/.env.dist"
}

@test "Ubuntu 20.04 is rejected as unsupported" {
    local utils="${BASE_DIR}/scripts/utils.sh"
    refute_grep -q '20\.04' "${utils}"
    refute_grep -q 'focal' "${utils}"
    grep -qF '"22.04" | "LM21"' "${utils}"
}

@test "nginx repo installer honors NGINX_REPO_SRC" {
    local nginx="${BASE_DIR}/scripts/install_nginx.sh"
    grep -qF 'NGINX_REPO_SRC:-myguard' "${nginx}"
    grep -qF 'NGINX_REPO_SOURCE="${SELECTED_REPO}"' "${nginx}"
    grep -qF 'NGINX_REPO_SRC="myguard"' "${BASE_DIR}/.env.dist"
}

@test "nginx post-install ships the CORS origin map" {
    grep -qF 'etc/nginx/cors" /etc/nginx/' \
        "${BASE_DIR}/scripts/nginx/nginx_post_install.sh"
}

@test "PHP-FPM pools keep temp files outside user homes (SEC-12)" {
    grep -q 'var/lib/php/lemper' "${BASE_DIR}/lib/lemper-create.sh"
    grep -q 'var/lib/php/lemper' "${BASE_DIR}/scripts/install_php.sh"
    refute_grep -q '\.lemper/tmp' "${BASE_DIR}/lib/lemper-create.sh"
    refute_grep -q '\.lemper/tmp' "${BASE_DIR}/scripts/install_php.sh"
    refute_grep -rq '\.lemper/php' "${BASE_DIR}/etc/php"
}

@test "unit test suite covers validators, PHP temp dirs, and DB backup/restore" {
    [ -f "${BASE_DIR}/tests/unit/validators.bats" ]
    [ -f "${BASE_DIR}/tests/unit/php_temp_dirs.bats" ]
    [ -f "${BASE_DIR}/tests/unit/db_backup_restore.bats" ]
    grep -q 'db_backup_database' "${BASE_DIR}/lib/lemper-db.sh"
    grep -q 'db_restore_database' "${BASE_DIR}/lib/lemper-db.sh"
}

@test "nginx blocks hidden files but keeps ACME challenges reachable (SEC-13)" {
    local cfg="${BASE_DIR}/etc/nginx/includes/rules_restriction.conf"
    local well_line deny_line
    well_line=$(grep -nF 'location ~ ^/.well-known/' "${cfg}" | head -1 | cut -d: -f1)
    deny_line=$(grep -nE '^location ~ /\\\.' "${cfg}" | head -1 | cut -d: -f1)
    [ -n "${well_line}" ]
    [ -n "${deny_line}" ]
    [ "${well_line}" -lt "${deny_line}" ]
}

@test "restriction rules are included before static-file rules" {
    local gen="${BASE_DIR}/lib/lemper-create.sh"
    local restrict_line static_line
    restrict_line=$(grep -n 'rules_restriction.conf' "${gen}" | head -1 | cut -d: -f1)
    static_line=$(grep -n 'rules_staticfiles.conf' "${gen}" | head -1 | cut -d: -f1)
    [ "${restrict_line}" -lt "${static_line}" ]
}

@test "static file locations preserve security headers" {
    local cfg="${BASE_DIR}/etc/nginx/includes/rules_staticfiles.conf"
    grep -qF 'include /etc/nginx/includes/security_headers.conf;' "${cfg}"
    # JSON is not cached for a year as immutable.
    refute_grep -qE '\\\.\(\?:wasm\|json\|map\)' "${cfg}"
    grep -qE '\\\.\(\?:wasm\|map\)' "${cfg}"
}

@test "PHP-FPM pools disable error display and harden sessions (SEC-14)" {
    local v pool conf
    for v in 8.2 8.3 8.4 8.5; do
        for pool in lemper www; do
            conf="${BASE_DIR}/etc/php/${v}/fpm/pool.d/${pool}.conf"
            grep -qF 'php_admin_flag[display_errors] = off' "${conf}"
            grep -qF 'php_admin_flag[display_startup_errors] = off' "${conf}"
            grep -qF 'php_admin_flag[expose_php] = off' "${conf}"
            grep -qF 'request_terminate_timeout = 300s' "${conf}"
            grep -qF 'php_admin_value[session.use_strict_mode] = 1' "${conf}"
            grep -qF 'php_admin_value[session.cookie_httponly] = 1' "${conf}"
            grep -qF 'php_admin_value[session.cookie_samesite] = Lax' "${conf}"
            # Session files must not be relocatable into the document root.
            grep -qF 'php_admin_value[session.save_path]' "${conf}"
            refute_grep -qF 'php_value[session.save_path]' "${conf}"
        done
    done
    grep -qF 'php_admin_flag[display_errors] = off' "${BASE_DIR}/lib/lemper-create.sh"
    grep -qF 'php_admin_flag[display_errors] = off' "${BASE_DIR}/scripts/install_php.sh"
    refute_grep -qF 'php_flag[display_errors] = on' "${BASE_DIR}/lib/lemper-create.sh"
    refute_grep -qF 'php_flag[display_errors] = on' "${BASE_DIR}/scripts/install_php.sh"
    # FPM php_flag only accepts on/off-style booleans, not "0".
    refute_grep -rqF 'php_flag[cgi.fix_pathinfo] = 0' "${BASE_DIR}/lib" "${BASE_DIR}/scripts" "${BASE_DIR}/etc/php"
    grep -qF 'php_flag[cgi.fix_pathinfo] = off' "${BASE_DIR}/lib/lemper-create.sh"
}

@test "FastCGI cache respects application cache headers (SEC-15)" {
    local cache="${BASE_DIR}/etc/nginx/includes/fastcgi_cache.conf"
    refute_grep -qE 'fastcgi_ignore_headers.*(Set-Cookie|Vary|Cache-Control)' "${cache}"
    refute_grep -qE '^fastcgi_cache_valid any' "${cache}"
    grep -qF 'fastcgi_ignore_headers Expires X-Accel-Expires;' "${cache}"
    # shellcheck disable=SC2016 # literal nginx variables
    grep -qF 'fastcgi_cache_key "$scheme$host$cache_uri";' "${BASE_DIR}/etc/nginx/fastcgi_cache"
    # shellcheck disable=SC2016 # literal nginx variables
    grep -qF 'fastcgi_cache_purge LEMPERCACHE "$scheme$host$1";' "${BASE_DIR}/etc/nginx/includes/rules_fastcgi_cache.conf"
    # Directives unsupported by the packaged ngx_cache_purge must not be used.
    refute_grep -rq 'cache_purge_response_type' "${BASE_DIR}/etc/nginx"
}

@test "generated PHP locations reject missing scripts and scope FPM status" {
    local gen="${BASE_DIR}/lib/lemper-create.sh"
    # shellcheck disable=SC2016 # generator escapes the literal $uri
    [ "$(grep -cF 'try_files \$uri =404;' "${gen}")" -ge 4 ]
    refute_grep -q 'allow all;' "${gen}"
    refute_grep -qE 'location ~ \\\.php \{' "${gen}"
    grep -qE 'location ~ \^/php-fpm_\(status\|ping\)\$' "${gen}"
}

@test "HSTS is not preloaded by default" {
    local ssl="${BASE_DIR}/etc/nginx/includes/ssl.conf"
    refute_grep -qE '^add_header Strict-Transport-Security .*preload' "${ssl}"
    grep -qE '^add_header Strict-Transport-Security "max-age=31536000"' "${ssl}"
}

@test "installer enables opcache for every PHP version" {
    grep -q 'opcache.enable=1' "${BASE_DIR}/scripts/install_php.sh"
    grep -q 'Custom Optimization for LEMPer' "${BASE_DIR}/scripts/install_php.sh"
}

@test "admin vhosts apply the same restriction rules" {
    local f
    for f in "${BASE_DIR}/etc/nginx/sites-available/default" \
             "${BASE_DIR}/etc/nginx/sites-available/default-ssl"; do
        [ "$(grep -c 'rules_security.conf' "${f}")" -ge 2 ]
        [ "$(grep -c 'rules_restriction.conf' "${f}")" -ge 2 ]
    done
}

@test "default vhosts share the PHP handler and monitoring includes" {
    local handlers="${BASE_DIR}/etc/nginx/includes/php_handlers.conf"
    local f

    [ -f "${handlers}" ]
    grep -qF 'location ~ \.php85$ {' "${handlers}"
    grep -qF 'location ~ \.php82$ {' "${handlers}"
    refute_grep -qF 'location ~ \.php81$ {' "${handlers}"
    grep -qF 'include /etc/nginx/includes/php_handler.conf;' "${handlers}"

    for f in "${BASE_DIR}/etc/nginx/sites-available/default" \
             "${BASE_DIR}/etc/nginx/sites-available/default-ssl"; do
        # Public server, nested /lcp area, and admin server.
        [ "$(grep -c 'include /etc/nginx/includes/php_handlers.conf;' "${f}")" -eq 3 ]
        [ "$(grep -c 'include /etc/nginx/includes/monitoring.conf;' "${f}")" -eq 1 ]
        grep -qF 'set $php_version "8.5";' "${f}"
        refute_grep -qF 'location ~ \.php85$ {' "${f}"
    done

    grep -qF 'fastcgi_pass unix:/run/php/php$php_version-fpm.sock;' \
        "${BASE_DIR}/etc/nginx/includes/monitoring.conf"
}

@test "compression config does not leak the stack name" {
    refute_grep -q 'X-Powered-By' "${BASE_DIR}/etc/nginx/includes/compression_gzip.conf"
}

@test "cache_static template preserves security headers" {
    grep -qF 'include /etc/nginx/includes/security_headers.conf;' \
        "${BASE_DIR}/etc/nginx/includes/cache_static.conf"
}

@test "FastCGI cache honors client revalidation requests" {
    local maps="${BASE_DIR}/etc/nginx/fastcgi_cache"
    local cache="${BASE_DIR}/etc/nginx/includes/fastcgi_cache.conf"
    grep -qF 'http_cache_control' "${maps}"
    grep -qF 'skip_cache_control' "${maps}"
    grep -qF 'skip_cache_control' "${cache}"
}

@test "restriction rules deny backups and dumps" {
    grep -qF 'sql|sqlite|db|dump' "${BASE_DIR}/etc/nginx/includes/rules_restriction.conf"
}

@test "restriction rules deny PHP session files in web roots" {
    local cfg="${BASE_DIR}/etc/nginx/includes/rules_restriction.conf"
    grep -qF '/sess_[' "${cfg}"
}

@test "static SVG responses are sandboxed" {
    local cfg="${BASE_DIR}/etc/nginx/includes/rules_staticfiles.conf"
    grep -qF 'Content-Security-Policy' "${cfg}"
    grep -qF 'sandbox' "${cfg}"
}

@test "generated vhosts enable gzip compression" {
    local gen="${BASE_DIR}/lib/lemper-create.sh"
    [ "$(grep -c '^    include /etc/nginx/includes/compression_gzip.conf;' "${gen}")" -ge 4 ]
    grep -qF 'include /etc/nginx/includes/compression_gzip.conf;' \
        "${BASE_DIR}/etc/nginx/sites-available/default"
}

@test "installer selects the low-end Nginx template on micro hosts" {
    local lowend="${BASE_DIR}/etc/nginx/nginx-lowend.conf"
    [ -f "${lowend}" ]
    grep -qF 'worker_processes 1;' "${lowend}"
    grep -qF 'worker_connections 512;' "${lowend}"
    grep -qF 'open_file_cache max=10000' "${lowend}"
    refute_grep -qE '^[[:space:]]*aio[[:space:]]+threads' "${lowend}"
    grep -qF 'fastcgi_https_map' "${lowend}"
    grep -qF 'sites-enabled' "${lowend}"
    grep -qF 'nginx-lowend.conf' "${BASE_DIR}/scripts/nginx/nginx_post_install.sh"
    grep -qF 'detect_resource_profile' "${BASE_DIR}/scripts/nginx/nginx_post_install.sh"
}

@test "resource profile knobs are documented in .env.dist" {
    local envfile="${BASE_DIR}/.env.dist"
    grep -qE '^SERVER_PROFILE="' "${envfile}"
    grep -qE '^PHP_FPM_MAX_CHILDREN="' "${envfile}"
    grep -qE '^PHP_MEMORY_LIMIT="' "${envfile}"
    grep -qE '^OPCACHE_MEMORY_MB="' "${envfile}"
    grep -qE '^SESSION_COOKIE_SECURE=' "${envfile}"
    grep -qE '^NGINX_ETAG="' "${envfile}"
    grep -qE '^DENY_ARCHIVE_FILES=' "${envfile}"
}

@test "PHP installer applies the resource profile to pools and opcache" {
    local install="${BASE_DIR}/scripts/install_php.sh"
    grep -qF 'detect_resource_profile' "${install}"
    grep -qF 'tune_php_pool' "${install}"
    # shellcheck disable=SC2016
    grep -qF 'opcache.memory_consumption=${OPCACHE_MEM}' "${install}"
    grep -qF 'calc_php_pool_sizing' "${BASE_DIR}/lib/lemper-create.sh"
}

@test "PHP extensions come from the repository only, without PECL or PEAR" {
    local install="${BASE_DIR}/scripts/install_php.sh"
    refute_grep -qE '^[[:space:]]*(run )?pecl( |$)' "${install}"
    refute_grep -q 'php-pear' "${install}"
    grep -qF 'not available from the distribution repository' "${install}"
    grep -qF 'https://github.com/php/pie' "${install}"
}

@test "bundled json and PHP 8.5 opcache are not resolved as packages" {
    local install="${BASE_DIR}/scripts/install_php.sh"
    grep -qF "grep -vx 'json'" "${install}"
    grep -qF '${PHPv//.} >= 85' "${install}"
    grep -qF "grep -vx 'opcache'" "${install}"
}

@test "PHP extensions are enabled for both SAPIs and verified through FPM" {
    local install="${BASE_DIR}/scripts/install_php.sh"

    grep -qE '^function enable_php_extension\(\)' "${install}"

    # Missing links are added per SAPI instead of reloading the CLI config.
    # shellcheck disable=SC2016
    grep -qF 'for SAPI in cli fpm; do' "${install}"
    grep -qF 'phpenmod -v "${PHPv}" -s "${SAPI}" "${EXT_NAME}"' "${install}"
    grep -qF '"php-fpm${PHPv}" -m' "${install}"

    # MongoDB and Redis delegate to the shared helper; the old CLI-only gate
    # ("php -m") must not decide whether FPM gets the extension.
    grep -qF 'enable_php_extension "${PHPv}" "mongodb"' "${install}"
    grep -qF 'enable_php_extension "${PHPv}" "redis"' "${install}"
    refute_grep -qF '"php${PHPv}" -m | grep' "${install}"
}

@test "re-running the PHP installer reconciles extensions for installed versions" {
    local install="${BASE_DIR}/scripts/install_php.sh"

    grep -qF 'is already installed, reconciling its extensions' "${install}"
    grep -qF 'PHP_WAS_INSTALLED' "${install}"
    grep -qF 'Installing missing PHP ${PHPv} extensions' "${install}"

    # A full re-run must not overwrite pools or logrotate on existing PHP.
    grep -qF 'if [[ "${PHP_ALREADY_INSTALLED}" == false ]]; then' "${install}"
    refute_grep -qF "and it's extensions already exists" "${install}"
}

@test "memcache tuning is only appended once" {
    local install="${BASE_DIR}/scripts/install_php.sh"
    grep -qF "grep -q 'Optimized for LEMPer stack.'" "${install}"
}

@test "deprecated PECL-only extensions are not in the default list" {
    local envfile="${BASE_DIR}/.env.dist"
    local exts
    exts=$(grep -E '^PHP_EXTENSIONS=' "${envfile}")
    [[ "${exts}" != *geoip* ]]
    [[ "${exts}" != *mcrypt* ]]
    grep -qF 'built manually with PIE' "${envfile}"
}

@test "Fail2ban install suppresses upstream Python SyntaxWarning noise" {
    grep -qF 'PYTHONWARNINGS=ignore::SyntaxWarning' "${BASE_DIR}/scripts/install_fail2ban.sh"
}

@test "MariaDB installer applies the resource profile" {
    local install="${BASE_DIR}/scripts/install_mariadb.sh"
    grep -qF 'tune_mariadb_config' "${install}"
    grep -qF 'calc_mariadb_sizing' "${install}"
    grep -qF '99-lemper-tuning.cnf' "${install}"
    grep -qF 'innodb_buffer_pool_size' "${install}"
}

@test "session cookie Secure is configurable per pool" {
    local v pool conf
    for v in 8.2 8.3 8.4 8.5; do
        for pool in lemper www; do
            conf="${BASE_DIR}/etc/php/${v}/fpm/pool.d/${pool}.conf"
            grep -qF 'php_admin_value[session.cookie_secure] = 0' "${conf}"
        done
    done
    # shellcheck disable=SC2016
    grep -qF 'php_admin_value[session.cookie_secure] = ${COOKIE_SECURE}' \
        "${BASE_DIR}/lib/lemper-create.sh"
    grep -qF 'php_admin_value[session.cookie_secure]' "${BASE_DIR}/scripts/install_php.sh"
}

@test "archive deny rules are shipped but opt-in" {
    [ -f "${BASE_DIR}/etc/nginx/includes/rules_archives.conf" ]
    grep -qF '#include /etc/nginx/includes/rules_archives.conf;' \
        "${BASE_DIR}/etc/nginx/includes/rules_restriction.conf"
    grep -qF 'DENY_ARCHIVE_FILES' "${BASE_DIR}/scripts/nginx/nginx_post_install.sh"
}

@test "rate limiting is wired through the shared security include" {
    local sec="${BASE_DIR}/etc/nginx/includes/rules_security.conf"
    grep -qF '#limit_req zone=req_limit_per_ip' "${sec}"
    grep -qF '#limit_conn conn_limit_per_ip' "${sec}"
    grep -qF 'rules_security.conf' "${BASE_DIR}/scripts/nginx/nginx_post_install.sh"
}


@test "WordPress config creation skips the masked-password DB check" {
    grep -qF -- '--dbpass="__LEMPER_DB_PASS__"' "${BASE_DIR}/lib/lemper-create.sh"
    grep -qF -- '--skip-check' "${BASE_DIR}/lib/lemper-create.sh"
}

@test "CLI provides helpers required by the site plugin" {
    local cli="${BASE_DIR}/bin/lemper-cli.sh"
    local fn
    for fn in sed_inplace sanitize_sed_replacement detect_resource_profile \
        calc_php_pool_sizing create_php_temp_dirs; do
        grep -qE "^function ${fn}\(\)" "${cli}"
    done
}

@test "SSH public key option updates RSA_PUB_KEY without sed" {
    local cli="${BASE_DIR}/lemper.sh"
    local security="${BASE_DIR}/scripts/server_security.sh"

    grep -qF -- '--with-ssh-pub-key)' "${cli}"
    grep -qF 'set_env_value .env RSA_PUB_KEY "${RSA_PUB_KEY}"' "${cli}"
    refute_grep -q 'SSH_PUB_KEY' "${cli}"

    grep -qF 'is_ssh_public_key "${RSA_PUB_KEY}"' "${security}"
    refute_grep -q 'RSA_PUB_KEY} =~ ssh-rsa' "${security}"
}

@test "HTTP/2 uses the http2 directive instead of the deprecated listen parameter" {
    local ssl_conf="${BASE_DIR}/etc/nginx/sites-available/default-ssl"
    local manage="${BASE_DIR}/lib/lemper-manage.sh"

    grep -qF 'http2 on;' "${ssl_conf}"
    refute_grep -rqE '^[[:space:]]*listen[^;]*http2' "${BASE_DIR}/etc/nginx"
    refute_grep -qE '^[[:space:]]*listen[^;]*http2' "${manage}"

    # Enabling SSL must switch HTTP/2 on for generated vhosts.
    grep -qF 'http2 on;' "${manage}"
    refute_grep -q '#ssl on;' "${BASE_DIR}/etc/nginx/includes/ssl.conf"
}

@test "rewrite_log is opt-in and paired with a notice-level error log" {
    grep -qF '#rewrite_log on;' "${BASE_DIR}/etc/nginx/nginx.conf"
    grep -qF '#rewrite_log on;' "${BASE_DIR}/etc/nginx/nginx-lowend.conf"
    grep -qF 'NGINX_REWRITE_LOG' "${BASE_DIR}/.env.dist"

    local post="${BASE_DIR}/scripts/nginx/nginx_post_install.sh"
    grep -qF 'rewrite_log on;' "${post}"
    grep -qF 'error.log notice;' "${post}"
}

@test "CORS can be enabled and disabled from the CLI" {
    local manage="${BASE_DIR}/lib/lemper-manage.sh"

    grep -qE '^function enable_cors\(\)' "${manage}"
    grep -qE '^function disable_cors\(\)' "${manage}"
    grep -qF -- '--enable-cors)' "${manage}"
    grep -qF -- '--disable-cors)' "${manage}"

    # Per-vhost wrapper defaults to a wildcard origin and pulls in the
    # shared header include; disabling removes the wrapper again.
    grep -qF 'set \$cors "*";' "${manage}"
    grep -qF 'include /etc/nginx/includes/cors.conf;' "${manage}"
    grep -qF 'cors-${DOMAIN}.conf' "${manage}"
    grep -qF 'CORS origin mapping' "${BASE_DIR}/etc/nginx/nginx.conf"
}

@test "uninstall leaves a pre-existing Nginx untouched unless forced" {
    local install="${BASE_DIR}/scripts/install_nginx.sh"
    local remove="${BASE_DIR}/scripts/remove_nginx.sh"
    local utils="${BASE_DIR}/scripts/utils.sh"

    grep -qE '^function mark_lemper_provisioned\(\)' "${utils}"
    grep -qE '^function lemper_provisioned\(\)' "${utils}"

    grep -qF 'mark_lemper_provisioned nginx' "${install}"
    grep -qF 'lemper_provisioned nginx' "${remove}"
    grep -qF 'FORCE_REMOVE' "${remove}"
    grep -qF 'was already installed before LEMPer' "${remove}"
}

@test "HTTP/3 is opt-in and gated on the nginx v3 module" {
    local post="${BASE_DIR}/scripts/nginx/nginx_post_install.sh"
    local manage="${BASE_DIR}/lib/lemper-manage.sh"

    grep -qF 'NGINX_HTTP3' "${BASE_DIR}/.env.dist"

    # Runtime config only applies when the binary advertises the module.
    grep -qF -- '--with-http_v3_module' "${post}"
    grep -qF 'listen 443 quic;' "${post}"
    grep -qF 'http3 on;' "${post}"
    grep -qF 'Alt-Svc' "${post}"
    grep -qF 'includes/http3.conf' "${post}"
    grep -qF 'includes/http3.conf' "${manage}"

    # The quictls builder requests v3, plain OpenSSL does not.
    grep -qF 'grep -iq quic' "${BASE_DIR}/scripts/nginx/nginx_ssl_builders.sh"
    grep -qF -- '--with-http_v3_module' "${BASE_DIR}/scripts/nginx/nginx_ssl_builders.sh"

    # QUIC needs UDP 443 through CSF.
    grep -qF 'UDP_IN' "${BASE_DIR}/scripts/server_security.sh"
}

@test "Adminer is installed from the official upstream release" {
    local tools="${BASE_DIR}/scripts/install_tools.sh"

    grep -qF 'github.com/vrana/adminer/releases/download' "${tools}"
    grep -qF 'adminer-${ADMINER_VERSION}.php' "${tools}"
    grep -qF 'editor-${ADMINER_VERSION}.php' "${tools}"
    grep -qF 'ADMINER_VERSION:-' "${tools}"
    grep -qE '^ADMINER_VERSION="' "${BASE_DIR}/.env.dist"

    # AdminerEvo has been deprecated in favor of upstream Adminer.
    refute_grep -qi 'github.com/adminerevo' "${tools}"
    refute_grep -qi 'adminerevo' "${BASE_DIR}/README.md"
}
