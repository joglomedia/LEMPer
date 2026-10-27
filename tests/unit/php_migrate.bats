#!/usr/bin/env bats
##
# EOL PHP migration: Nginx vhost handlers and destination FPM pools.
# Assertions use [ ] and grep so a failing check is visible to Bash 3.2.
##

setup() {
    export REAL_BASE_DIR="${BATS_TEST_DIRNAME}/../.."
    export LEMPER_UPDATE_LIB_ONLY=true
    export PHP_ETC_DIR="${BATS_TEST_TMPDIR}/etc/php"
    export LEMPER_BACKUP_DIR="${BATS_TEST_TMPDIR}/backups"
    export LEMPER_PHP_STATE_DIR="${BATS_TEST_TMPDIR}/php-state"
    export LEMPER_NGINX_SITES_DIR="${BATS_TEST_TMPDIR}/nginx/sites-available"
    export LEMPER_NGINX_SITES_ENABLED="${BATS_TEST_TMPDIR}/nginx/sites-enabled"
    export TMPDIR="${BATS_TEST_TMPDIR}"
    export NGINX_CALLED_LOG="${BATS_TEST_TMPDIR}/nginx-called"

    mkdir -p "${PHP_ETC_DIR}/8.3/fpm/pool.d" \
        "${PHP_ETC_DIR}/8.1/fpm/pool.d" \
        "${LEMPER_BACKUP_DIR}" \
        "${LEMPER_PHP_STATE_DIR}" \
        "${LEMPER_NGINX_SITES_DIR}" \
        "${LEMPER_NGINX_SITES_ENABLED}" \
        "${BATS_TEST_TMPDIR}/bin"

    cat > "${BATS_TEST_TMPDIR}/bin/nginx" <<'EOF'
#!/bin/sh
echo called >> "${NGINX_CALLED_LOG}"
exit 1
EOF
    chmod +x "${BATS_TEST_TMPDIR}/bin/nginx"
    export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
}

# shellcheck disable=SC2016
load_update_lib='
    info() { printf "INFO: %s\n" "$*"; }
    warning() { printf "WARN: %s\n" "$*"; }
    error() { printf "ERROR: %s\n" "$*"; }
    success() { printf "OK: %s\n" "$*"; }
    fail() { printf "FAIL: %s\n" "$*"; exit 1; }
    requires_root() { :; }
    PROG_NAME="lemper-cli"
    LEMPER_UPDATE_LIB_ONLY=true
    . "${REAL_BASE_DIR}/lib/lemper-update.sh"
'

run_migrate() {
    bash -c "${load_update_lib}"' "$@"' _ "$@"
}

refute_grep() {
    run grep "$@"
    [ "${status}" -ne 0 ]
}

@test "socket parser reads the pool user and the bare www socket" {
    run run_migrate php_parse_fpm_socket "fastcgi_pass unix:/run/php/php8.1-fpm.alice.sock;"
    [ "${status}" -eq 0 ]
    [ "${output}" = $'8.1\talice' ]

    run run_migrate php_parse_fpm_socket "fastcgi_pass unix:/run/php/php8.1-fpm.sock;"
    [ "${status}" -eq 0 ]
    [ "${output}" = $'8.1\twww' ]
}

@test "EOL sockets move to the target and supported sockets stay" {
    run run_migrate php_migrate_fastcgi_line "fastcgi_pass unix:/run/php/php8.1-fpm.alice.sock;" 8.3
    [ "${status}" -eq 0 ]
    [ "${output}" = "fastcgi_pass unix:/run/php/php8.3-fpm.alice.sock;" ]

    run run_migrate php_migrate_fastcgi_line "fastcgi_pass unix:/run/php/php8.2-fpm.carol.sock;" 8.3
    [ "${status}" -eq 0 ]
    [ "${output}" = "fastcgi_pass unix:/run/php/php8.2-fpm.carol.sock;" ]

    run run_migrate php_migrate_fastcgi_line 'fastcgi_pass unix:/run/php/php$php_version-fpm.sock;' 8.3
    [ "${status}" -eq 0 ]
    [ "${output}" = 'fastcgi_pass unix:/run/php/php$php_version-fpm.sock;' ]
}

@test "migration copies the EOL pool and rewrites every EOL socket" {
    local vhost="${LEMPER_NGINX_SITES_DIR}/app.conf"
    local src="${PHP_ETC_DIR}/8.1/fpm/pool.d/alice.conf"
    local dest="${PHP_ETC_DIR}/8.3/fpm/pool.d/alice.conf"

    cat > "${src}" <<'EOF'
listen = /run/php/php8.1-fpm.$pool.sock
security.limit_extensions = .php .php81
pm.max_children = 42
EOF
    cat > "${vhost}" <<'EOF'
fastcgi_pass unix:/run/php/php8.1-fpm.alice.sock;
fastcgi_pass unix:/run/php/php8.0-fpm.bob.sock;
fastcgi_pass unix:/run/php/php8.2-fpm.carol.sock;
# fastcgi_pass unix:/run/php/php8.1-fpm.old.sock;
EOF

    run run_migrate php_migrate_eol_sites 8.3
    [ "${status}" -eq 0 ]
    grep -q 'php8.3-fpm.alice.sock' "${vhost}"
    grep -q 'php8.3-fpm.bob.sock' "${vhost}"
    grep -q 'php8.2-fpm.carol.sock' "${vhost}"
    grep -q 'php8.1-fpm.old.sock' "${vhost}"
    refute_grep -q 'php8.1-fpm.alice.sock' "${vhost}"

    grep -q 'php8.3-fpm.$pool.sock' "${dest}"
    grep -q '.php83' "${dest}"
    grep -q 'pm.max_children = 42' "${dest}"
    refute_grep -q 'memory_limit' "${dest}"
    grep -q 'user = bob' "${PHP_ETC_DIR}/8.3/fpm/pool.d/bob.conf"
    grep -q 'php8.3-fpm.bob.sock' "${PHP_ETC_DIR}/8.3/fpm/pool.d/bob.conf"
    [ ! -f "${NGINX_CALLED_LOG}" ]
}

@test "a missing EOL pool becomes a minimal pool for that user" {
    local vhost="${LEMPER_NGINX_SITES_DIR}/bare.conf"
    printf '%s\n' 'fastcgi_pass unix:/run/php/php8.1-fpm.sock;' > "${vhost}"

    run run_migrate php_migrate_eol_sites 8.3
    [ "${status}" -eq 0 ]
    grep -q 'user = www-data' "${PHP_ETC_DIR}/8.3/fpm/pool.d/www.conf"
    grep -q 'listen = /run/php/php8.3-fpm.sock' "${PHP_ETC_DIR}/8.3/fpm/pool.d/www.conf"
    [ -d "${LEMPER_PHP_STATE_DIR}/www/sessions" ]
}

@test "an existing destination pool is kept" {
    local vhost="${LEMPER_NGINX_SITES_DIR}/keep.conf"
    local dest="${PHP_ETC_DIR}/8.3/fpm/pool.d/alice.conf"
    printf '%s\n' 'KEEP' > "${dest}"
    printf '%s\n' 'listen = /run/php/php8.1-fpm.alice.sock' > "${PHP_ETC_DIR}/8.1/fpm/pool.d/alice.conf"
    printf '%s\n' 'fastcgi_pass unix:/run/php/php8.1-fpm.alice.sock;' > "${vhost}"

    run run_migrate php_migrate_eol_sites 8.3
    [ "${status}" -eq 0 ]
    grep -q 'php8.3-fpm.alice.sock' "${vhost}"
    [ "$(cat "${dest}")" = "KEEP" ]
}

@test "set php_version lines for EOL releases move to the www pool" {
    local vhost="${LEMPER_NGINX_SITES_DIR}/default.conf"
    cat > "${vhost}" <<'EOF'
set $php_version "8.1";
set $php_version "8.2";
EOF
    printf '%s\n' 'listen = /run/php/php8.1-fpm.sock' > "${PHP_ETC_DIR}/8.1/fpm/pool.d/www.conf"

    run run_migrate php_migrate_eol_sites 8.3
    [ "${status}" -eq 0 ]
    grep -q 'set $php_version "8.3";' "${vhost}"
    grep -q 'set $php_version "8.2";' "${vhost}"
    grep -q 'php8.3-fpm.sock' "${PHP_ETC_DIR}/8.3/fpm/pool.d/www.conf"
}

@test "a sites-enabled symlink is migrated once" {
    local vhost="${LEMPER_NGINX_SITES_DIR}/once.conf"
    printf '%s\n' 'fastcgi_pass unix:/run/php/php8.1-fpm.alice.sock;' > "${vhost}"
    ln -s "${vhost}" "${LEMPER_NGINX_SITES_ENABLED}/once.conf"
    printf '%s\n' 'user = alice' > "${PHP_ETC_DIR}/8.1/fpm/pool.d/alice.conf"

    run run_migrate php_migrate_eol_sites 8.3
    [ "${status}" -eq 0 ]
    [ "$(grep -c 'php8.3-fpm.alice.sock' "${vhost}")" -eq 1 ]

    local manifest
    manifest=$(find "${LEMPER_BACKUP_DIR}" -name manifest.tsv | head -n 1)
    [ -n "${manifest}" ]
    [ "$(grep -c . "${manifest}")" -eq 1 ]
}

@test "EOL and unknown targets are refused before vhosts change" {
    local vhost="${LEMPER_NGINX_SITES_DIR}/stay.conf"
    printf '%s\n' 'fastcgi_pass unix:/run/php/php8.1-fpm.alice.sock;' > "${vhost}"

    run run_migrate php_migrate_eol_sites 8.1
    [ "${status}" -ne 0 ]
    grep -q 'php8.1-fpm.alice.sock' "${vhost}"

    run run_migrate php_migrate_eol_sites 7.4
    [ "${status}" -ne 0 ]
    grep -q 'php8.1-fpm.alice.sock' "${vhost}"

    run run_migrate php_migrate_eol_sites 8.4
    [ "${status}" -ne 0 ]
    echo "${output}" | grep -q 'not installed'
    grep -q 'php8.1-fpm.alice.sock' "${vhost}"

    run bash -c "${load_update_lib}"'
        PHP_MIGRATE_TO=8.1
        update_php
    '
    [ "${status}" -ne 0 ]
    echo "${output}" | grep -q 'not a supported migration target'
}

@test "update php names the migrate command until a destination is given" {
    run bash -c "${load_update_lib}"'
        php_package_version() {
            php_fixed_version "$1" && return 0
            printf "8.1.33\n"
        }
        php_mitigate_branch() { return 0; }
        php_patch_branch() { printf "PATCH %s\n" "$1"; return 1; }
        update_php
    '
    [ "${status}" -ne 0 ]
    echo "${output}" | grep -q 'update php --migrate-to=8.3'
}

@test "update php migrates when the destination is installed" {
    local vhost="${LEMPER_NGINX_SITES_DIR}/moved.conf"
    printf '%s\n' 'fastcgi_pass unix:/run/php/php8.1-fpm.alice.sock;' > "${vhost}"
    printf '%s\n' 'listen = /run/php/php8.1-fpm.alice.sock' > "${PHP_ETC_DIR}/8.1/fpm/pool.d/alice.conf"

    run bash -c "${load_update_lib}"'
        php_package_version() {
            php_fixed_version "$1" && return 0
            printf "8.1.33\n"
        }
        php_mitigate_branch() { printf "MITIGATED %s\n" "$1"; return 0; }
        php_patch_branch() { printf "PATCH %s\n" "$1"; return 1; }
        PHP_MIGRATE_TO=8.3
        update_php
    '
    [ "${status}" -eq 0 ]
    grep -q 'php8.3-fpm.alice.sock' "${vhost}"
    echo "${output}" | grep -q 'MITIGATED 8.1'
    refute_grep -q 'memory_limit' "${PHP_ETC_DIR}/8.3/fpm/pool.d/alice.conf"
}

@test "migration flags require an explicit supported version" {
    run run_migrate update_parse_args --force
    [ "${status}" -ne 0 ]
    echo "${output}" | grep -q 'migrate-to=8.3'

    run run_migrate update_parse_args --migrate-to=
    [ "${status}" -ne 0 ]

    run run_migrate update_parse_args --migrate-to
    [ "${status}" -ne 0 ]

    run bash -c "${load_update_lib}"'
        update_parse_args --force=8.3
        printf "%s\n" "${PHP_MIGRATE_TO}"
    '
    [ "${status}" -eq 0 ]
    [ "${output}" = "8.3" ]

    run bash -c "${load_update_lib}"'
        update_parse_args --migrate-to 8.4
        printf "%s\n" "${PHP_MIGRATE_TO}"
    '
    [ "${status}" -eq 0 ]
    [ "${output}" = "8.4" ]

    run run_migrate update_help
    [ "${status}" -eq 0 ]
    echo "${output}" | grep -q -- '--force=8.3'
}

@test "PHP 8.1 is out of the default install set and still removable" {
    grep -q 'PHP_VERSIONS="8.2 8.3 8.4 8.5"' "${REAL_BASE_DIR}/.env.dist"
    refute_grep -q 'PHP 8.1 (EOL)' "${REAL_BASE_DIR}/scripts/install_php.sh"
    grep -q 'PHP 8.1 (EOL)' "${REAL_BASE_DIR}/scripts/remove_php.sh"
    [ ! -d "${REAL_BASE_DIR}/etc/php/8.1" ]
}
