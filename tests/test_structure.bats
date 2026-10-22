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

@test "lemper-stacks.sh wires in Bun.js install/remove" {
    grep -q 'install_bun.sh' "${BASE_DIR}/lib/core/lemper-stacks.sh"
    grep -q 'remove_bun.sh' "${BASE_DIR}/lib/core/lemper-stacks.sh"
}

@test "site-list plugin has validate_fqdn function" {
    grep -q 'function validate_fqdn' "${BASE_DIR}/lib/lemper-site-list.sh"
}

@test "install_redis.sh supports Valkey backend" {
    grep -q 'add_valkey_repo' "${BASE_DIR}/scripts/install_redis.sh"
    grep -q 'REDIS_BACKEND' "${BASE_DIR}/scripts/install_redis.sh"
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

@test "install_crowdsec.sh and remove_crowdsec.sh exist" {
    [ -f "${BASE_DIR}/scripts/install_crowdsec.sh" ]
    [ -f "${BASE_DIR}/scripts/remove_crowdsec.sh" ]
}

@test "lemper-stacks.sh wires in CrowdSec install/remove" {
    grep -q 'install_crowdsec.sh' "${BASE_DIR}/lib/core/lemper-stacks.sh"
    grep -q 'remove_crowdsec.sh' "${BASE_DIR}/lib/core/lemper-stacks.sh"
}

@test "CrowdSec install includes WordPress web app scenarios" {
    grep -q 'install_crowdsec_webapp_support' "${BASE_DIR}/scripts/install_crowdsec.sh"
    grep -q 'crowdsecurity/wordpress' "${BASE_DIR}/scripts/install_crowdsec.sh"
    grep -q 'wordpress-xmlrpc' "${BASE_DIR}/scripts/install_crowdsec.sh"
    grep -q 'wordpress-bruteforce' "${BASE_DIR}/scripts/install_crowdsec.sh"
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

@test "install_modsec.sh and remove_modsec.sh exist" {
    [ -f "${BASE_DIR}/scripts/install_modsec.sh" ]
    [ -f "${BASE_DIR}/scripts/remove_modsec.sh" ]
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
    grep -q 'aes-256-gcm' "${BASE_DIR}/lib/lemper-encrypt.sh"
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

@test "Podman test script defaults to Ubuntu 24.04" {
    grep -q 'ubuntu:24.04' "${BASE_DIR}/scripts/test_podman.sh"
}
