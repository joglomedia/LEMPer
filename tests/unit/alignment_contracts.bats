#!/usr/bin/env bats
load env_helper
setup() {
    unit_setup
    export LEMPER_OPERATION_LOCK="$TEST_TMPDIR/operation.lock"
    export LEMPER_NGINX_DIR="$TEST_TMPDIR/nginx"
    export LEMPER_SITE_STATE_DIR="$TEST_TMPDIR/sites"
    export LEMPER_INSTALLED_DIR="$TEST_TMPDIR/installed"
    mkdir -p "$LEMPER_NGINX_DIR"/sites-{available,enabled} "$LEMPER_SITE_STATE_DIR" "$LEMPER_INSTALLED_DIR"
    printf 'original\n' > "$LEMPER_NGINX_DIR/sites-available/example.com.conf"
    printf 'original\n' > "$LEMPER_NGINX_DIR/sites-available/second.example.com.conf"
}
# shellcheck disable=SC2016 # This fixture is evaluated by the child shell.
alignment_child='
    . "$REAL_BASE_DIR/lib/core/loader.sh"
    requires_root() { :; }
    error() { printf "%s\n" "$*" >&2; }
    info() { printf "%s\n" "$*"; }
    PROG_NAME=lemperctl
    PROG_VERSION=test
    CMD_PARENT=lemperctl
    DRYRUN=false
'
@test "public help and version work without root or configuration" {
    run test_run_public "$REAL_BASE_DIR" bin/lemper-cli.sh site create --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--runtime-user"* ]]
    run test_run_public "$REAL_BASE_DIR" bin/lemper-cli.sh --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"version 4.0.0"* ]]
}
@test "source-only runtime and driver modules neither dispatch nor initialize" {
    run bash -c '
        for module in "$1"/lib/runtime/*/*.sh "$1"/lib/services/**/*.sh "$1"/lib/compat/*.sh; do
            . "$module" || exit 1
        done
        echo SOURCED
    ' _ "$REAL_BASE_DIR"
    [ "$status" -eq 0 ]
    [ "$output" = SOURCED ]
}
@test "issue create syntax normalizes to legacy input and records ownership" {
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/site/commands
        lemper_load_module services/php/lifecycle
        . "$REAL_BASE_DIR/lib/compat/site.sh"
        . "$REAL_BASE_DIR/lib/services/nginx/site.sh"
        . "$REAL_BASE_DIR/lib/runtime/site/state.sh"
        rm "$LEMPER_NGINX_DIR/sites-available/example.com.conf"
        lemper_legacy_site_create() {
            mkdir -p "$TEST_TMPDIR/web root/wp-includes"
            printf "<?php // WordPress fixture\n" > "$TEST_TMPDIR/web root/wp-includes/class-wp.php"
            printf "<?php // Entry fixture\n" > "$TEST_TMPDIR/web root/index.php"
            printf "<%s>\n" "$@"
            printf "set \$root_path \"%s\";\n" "$TEST_TMPDIR/web root" > "$LEMPER_NGINX_DIR/sites-available/example.com.conf"
        }
        nginx() { :; }
        lemper_site_create example.com --type=wordpress --runtime=php@8.5 --runtime-user=root --install-skeleton --webroot="$TEST_TMPDIR/web root"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"<--domain-name>"*"<example.com>"* ]]
    [[ "$output" == *"<--php-version>"*"<8.5>"* ]]
    [[ "$output" == *"<--install-app>"* ]]
    [ "$(stat -c %a "$LEMPER_SITE_STATE_DIR/example.com.conf")" = 600 ]
    grep -qx "WEBROOT=$TEST_TMPDIR/web root" "$LEMPER_SITE_STATE_DIR/example.com.conf"
    grep -q '^OWNER=root$' "$LEMPER_SITE_STATE_DIR/example.com.conf"
}
@test "create rejects conflicting aliases and EOL installs before invoking legacy code" {
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/site/commands
        lemper_site_create example.com --type=wordpress --framework=laravel --dry-run
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *"Conflicting type"* ]]
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/site/commands
        lemper_site_create example.com --runtime=php@8.1 --dry-run
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *"Supported PHP"* ]]
}
@test "site batch normalizes aliases, targets and actions and reloads once" {
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/site/commands
        . "$REAL_BASE_DIR/lib/services/nginx/site.sh"
        lemper_legacy_site_action() { printf "%s:%s\n" "$1" "$2"; }
        lemper_nginx_site_reload() { echo RELOAD; }
        lemper_site_change update example.com second.example.com --enable-ssl --cors-enable
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ssl-enable:example.com"* ]]
    [[ "$output" == *"cors-enable:second.example.com"* ]]
    [ "$(printf '%s\n' "$output" | grep -c '^RELOAD$')" -eq 1 ]
}
@test "batch rejects conflicting actions and invalid later targets before mutation" {
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/site/commands
        . "$REAL_BASE_DIR/lib/services/nginx/site.sh"
        lemper_legacy_site_action() { echo MUTATED; }
        lemper_site_change update example.com --ssl-enable --ssl-disable
    '
    [ "$status" -ne 0 ]
    [[ "$output" != *MUTATED* ]]
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/site/commands
        . "$REAL_BASE_DIR/lib/services/nginx/site.sh"
        lemper_legacy_site_action() { echo MUTATED; }
        lemper_site_change update example.com ../../etc --cors-enable
    '
    [ "$status" -ne 0 ]
    [[ "$output" != *MUTATED* ]]
}
@test "failed site action restores that target and reports failure after other targets" {
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/site/commands
        . "$REAL_BASE_DIR/lib/services/nginx/site.sh"
        lemper_legacy_site_action() {
            echo changed > "$LEMPER_NGINX_DIR/sites-available/$2.conf"
            [[ "$2" != example.com ]]
        }
        lemper_nginx_site_reload() { :; }
        lemper_site_change update example.com second.example.com --cors-enable
    '
    [ "$status" -ne 0 ]
    [ "$(cat "$LEMPER_NGINX_DIR/sites-available/example.com.conf")" = original ]
    [ "$(cat "$LEMPER_NGINX_DIR/sites-available/second.example.com.conf")" = changed ]
}
@test "reload failure restores every changed site configuration" {
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/site/commands
        . "$REAL_BASE_DIR/lib/services/nginx/site.sh"
        lemper_legacy_site_action() { echo changed > "$LEMPER_NGINX_DIR/sites-available/$2.conf"; }
        lemper_nginx_site_reload() { return 1; }
        lemper_site_change update example.com --cors-enable
    '
    [ "$status" -ne 0 ]
    [ "$(cat "$LEMPER_NGINX_DIR/sites-available/example.com.conf")" = original ]
}
@test "default site removal retains data and purge requires ownership metadata" {
    mkdir "$TEST_TMPDIR/webroot"
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/site/commands
        . "$REAL_BASE_DIR/lib/services/nginx/site.sh"
        . "$REAL_BASE_DIR/lib/runtime/site/state.sh"
        lemper_nginx_site_reload() { :; }
        lemper_site_change remove example.com --yes
    '
    [ "$status" -eq 0 ]
    [ -d "$TEST_TMPDIR/webroot" ]
    [ ! -e "$LEMPER_NGINX_DIR/sites-available/example.com.conf" ]
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/site/commands
        . "$REAL_BASE_DIR/lib/services/nginx/site.sh"
        . "$REAL_BASE_DIR/lib/runtime/site/state.sh"
        lemper_site_change remove second.example.com --purge --yes
    '
    [ "$status" -ne 0 ]
    [ -f "$LEMPER_NGINX_DIR/sites-available/second.example.com.conf" ]
}
@test "purge dry-run checks ownership and leaves data and configuration unchanged" {
    mkdir "$TEST_TMPDIR/webroot"
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/site/commands
        . "$REAL_BASE_DIR/lib/services/nginx/site.sh"
        . "$REAL_BASE_DIR/lib/runtime/site/state.sh"
        lemper_site_record example.com root "$TEST_TMPDIR/webroot" php@8.5 false
        lemper_site_change remove example.com --purge --dry-run
    '
    [ "$status" -eq 0 ]
    [ -d "$TEST_TMPDIR/webroot" ]
    [ -f "$LEMPER_NGINX_DIR/sites-available/example.com.conf" ]
}
@test "PHP control enumerates installed FPM versions including EOL and preserves failures" {
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/stack/commands
        dpkg-query() { printf "php8.1-fpm\tinstall ok installed\nphp8.4-fpm\tinstall ok installed\n"; }
        stack_control() { echo "$2"; [[ "$2" != php8.1-fpm ]]; }
        init_lemper_stack restart php
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *php8.1-fpm*php8.4-fpm* ]]
}
@test "PHP removal allows installed EOL selection and protects site references" {
    touch "$LEMPER_INSTALLED_DIR/php-8.1"
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/stack/commands
        dpkg-query() { printf "php8.1-fpm\tinstall ok installed\n"; }
        stack_run_component() { echo "REMOVE:$4"; }
        init_lemper_stack remove php --php-version 8.1 --yes --source-dir "$REAL_BASE_DIR"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *REMOVE:8.1* ]]
    printf 'fastcgi_pass unix:/run/php/php8.1-fpm.sock;\n' > "$LEMPER_NGINX_DIR/sites-available/example.com.conf"
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/stack/commands
        dpkg-query() { printf "php8.1-fpm\tinstall ok installed\n"; }
        stack_run_component() { echo MUTATED; }
        init_lemper_stack remove php --php-version 8.1 --force --yes --source-dir "$REAL_BASE_DIR"
    '
    [ "$status" -ne 0 ]
    [[ "$output" != *MUTATED* ]]
}
@test "selected PHP update is forwarded and version options reject unrelated services" {
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/stack/commands
        dpkg-query() { printf "php8.4-fpm\tinstall ok installed\nphp8.5-fpm\tinstall ok installed\n"; }
        lemper_exec() { printf "<%s>\n" "$@"; }
        php-fpm8.4() { [ "$1" = -t ]; }
        init_lemper_stack update php --php-version 8.4
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"<--php-version>"*"<8.4>"* ]]
    [[ "$output" != *"<8.5>"* ]]
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/stack/commands
        init_lemper_stack restart nginx --php-version 8.4
    '
    [ "$status" -ne 0 ]
}
@test "PHP updater constrains discovery to the selected branch" {
    run bash -c "${alignment_child}"'
        LEMPER_UPDATE_LIB_ONLY=true
        . "$REAL_BASE_DIR/lib/lemper-update.sh"
        PHP_UPDATE_VERSION=8.4
        php_installed_branches() { printf "8.4\n8.5\n"; }
        php_package_version() { echo "$1" >> "$TEST_TMPDIR/branches"; echo fixed; }
        php_branch_state() { echo patched; }
        update_php
    '
    [ "$status" -eq 0 ]
    [ "$(cat "$TEST_TMPDIR/branches")" = 8.4 ]
}
@test "registry recipes resolve service implementations and public aliases" {
    run bash -c "${alignment_child}"'
        for action in install remove; do
            while IFS= read -r service; do
                read -r installer remover _ < <(lemper_component_spec "$service")
                if [[ "$action" == install ]]; then name="$installer"; else name="$remover"; fi
                [[ "$name" == - || -f "$REAL_BASE_DIR/scripts/${action}_$name.sh" ]] || exit 1
            done < <(lemper_component_recipe "$action")
        done
        while IFS=: read -r name _; do
            [[ -f "$REAL_BASE_DIR/lib/$name.sh" ]] || exit 1
        done < <(lemper_command_plugins)
    '
    [ "$status" -eq 0 ]
}

@test "public CLI executes the issue create form as a safe dry run" {
    run env LEMPER_CONFIG_FILE="$TEST_TMPDIR/.env" bash "$REAL_BASE_DIR/bin/lemper-cli.sh" \
        site create example.com --type=wordpress --runtime=php@8.5 \
        --runtime-user=root --install-skeleton --webroot="$TEST_TMPDIR/webroot" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Would create example.com"* ]]
    [ ! -d "$TEST_TMPDIR/webroot" ]
}
@test "site enable, delete and manage aliases dispatch through the same adapter" {
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/site/commands
        init_lemper_site enable example.com --dry-run
        init_lemper_site manage --ssl-enable example.com --dry-run
        init_lemper_site delete second.example.com --dry-run
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"actions: enable"* ]]
    [[ "$output" == *"actions: ssl-enable"* ]]
    [[ "$output" == *"Would remove second.example.com"* ]]
}
@test "a retained site can be purged after its configuration was unregistered" {
    mkdir "$TEST_TMPDIR/webroot"
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/site/commands
        . "$REAL_BASE_DIR/lib/services/nginx/site.sh"
        . "$REAL_BASE_DIR/lib/runtime/site/state.sh"
        lemper_site_record example.com root "$TEST_TMPDIR/webroot" php@8.5 false
        lemper_nginx_site_reload() { :; }
        lemper_site_change remove example.com --yes || exit 1
        lemper_site_change remove example.com --purge --yes
    '
    [ "$status" -eq 0 ]
    [ ! -d "$TEST_TMPDIR/webroot" ]
    [ ! -f "$LEMPER_SITE_STATE_DIR/example.com.conf" ]
}
@test "purge refuses a webroot shared with another configured site" {
    mkdir "$TEST_TMPDIR/webroot"
    # shellcheck disable=SC2016 # Literal Nginx variable in fixture.
    printf 'set $root_path "%s";\n' "$TEST_TMPDIR/webroot" > "$LEMPER_NGINX_DIR/sites-available/second.example.com.conf"
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/site/commands
        . "$REAL_BASE_DIR/lib/services/nginx/site.sh"
        . "$REAL_BASE_DIR/lib/runtime/site/state.sh"
        lemper_site_record example.com root "$TEST_TMPDIR/webroot" php@8.5 false
        lemper_site_change remove example.com --purge --yes
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *"Shared webroot"* ]]
    [ -f "$LEMPER_NGINX_DIR/sites-available/example.com.conf" ]
    [ -d "$TEST_TMPDIR/webroot" ]
}

@test "purge passes database identifiers literally and keeps credentials off argv" {
    mkdir "$TEST_TMPDIR/webroot"
    run bash -c "${alignment_child}"'
        . "$REAL_BASE_DIR/lib/runtime/site/state.sh"
        lemper_site_record example.com root "$TEST_TMPDIR/webroot" php@8.5 false
        set_env_value "$LEMPER_SITE_STATE_DIR/example.com.conf" DATABASE app_synthetic
        MYSQL_ROOT_PASSWORD=synthetic-secret
        mysql() { printf "<%s>\n" "$@"; }
        app_synthetic() { echo EXECUTED; }
        lemper_site_purge_data example.com
    '
    [ "$status" -eq 0 ]
    # shellcheck disable=SC2016 # SQL quoting must stay literal in argv.
    [[ "$output" == *'DROP DATABASE IF EXISTS `app_synthetic`;'* ]]
    [[ "$output" != *EXECUTED* ]]
    [[ "$output" != *synthetic-secret* ]]
}
@test "legacy component adapter forwards PHP selection inside an isolated process" {
    mkdir -p "$TEST_TMPDIR/component/scripts"
    printf 'placeholder\n' > "$TEST_TMPDIR/component/.env.dist"
    cat > "$TEST_TMPDIR/component/scripts/utils.sh" <<'FIXTURE'
function is_config_encrypted() { return 1; }
function requires_root() { :; }
function preflight_system_check() { :; }
FIXTURE
    cat > "$TEST_TMPDIR/component/scripts/remove_php.sh" <<'FIXTURE'
printf 'PHP=%s DEFAULT=%s\n' "$PHP_VERSIONS" "$DEFAULT_PHP_VERSION"
exit 7
FIXTURE
    run bash -c "${alignment_child}"'
        lemper_load_module compat/components
        CONFIG_FILE="$TEST_TMPDIR/.env"
        is_config_encrypted() { return 1; }
        PHP_VERSIONS=8.5
        lemper_legacy_component remove php "$TEST_TMPDIR/component" 8.1 INSTALL_PHP "$TEST_TMPDIR/component/scripts/remove_php.sh" false
        result=$?
        echo "PARENT=$PHP_VERSIONS"
        exit "$result"
    '
    [ "$status" -eq 7 ]
    [[ "$output" == *"PHP=8.1 DEFAULT=8.1"* ]]
    [[ "$output" == *"PARENT=8.5"* ]]
}

@test "adoption records an existing owned site and refuses mismatched roots" {
    mkdir "$TEST_TMPDIR/webroot" "$TEST_TMPDIR/unrelated"
    # shellcheck disable=SC2016 # Literal Nginx variable in fixture.
    printf 'set $root_path "%s";\n' "$TEST_TMPDIR/webroot" > "$LEMPER_NGINX_DIR/sites-available/example.com.conf"
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/site/commands
        init_lemper_site adopt example.com --runtime-user=root --runtime=php@8.1 --yes
    '
    [ "$status" -eq 0 ]
    grep -q '^OWNER_MARKER=lemper-site-v1$' "$LEMPER_SITE_STATE_DIR/example.com.conf"
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/site/commands
        init_lemper_site adopt example.com --runtime-user=root --runtime=php@8.1 --webroot="$TEST_TMPDIR/unrelated" --yes
    '
    [ "$status" -ne 0 ]
    grep -q "WEBROOT=$TEST_TMPDIR/webroot" "$LEMPER_SITE_STATE_DIR/example.com.conf"
}

@test "legacy flag values and remove flag normalize without cross-target expansion" {
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/site/commands
        init_lemper_site update --enable-ssl=example.com --dry-run
        init_lemper_site mod --remove example.com --dry-run
        init_lemper_site update -sexample.com --dry-run
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"actions: ssl-enable"* ]]
    [[ "$output" == *"Would remove example.com"* ]]
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/site/commands
        init_lemper_site update --enable-ssl example.com --enable-cors second.example.com --dry-run
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *"Ambiguous legacy"* ]]
}

@test "PHP package update keeps a stopped FPM instance stopped" {
    run bash -c "${alignment_child}"'
        lemper_load_module services/php/lifecycle
        dpkg-query() { printf "php8.4-fpm\tinstall ok installed\n"; }
        lemper_exec() { printf "<%s>\n" "$@"; }
        systemctl() { [[ "$1" != is-active ]]; }
        lemper_service_control() { echo CONTROLLED; return 1; }
        lemper_php_update 8.4
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"<--only-upgrade>"*"<php8.4-fpm>"* ]]
    [[ "$output" != *CONTROLLED* ]]
}

@test "batch prepares every recovery snapshot before mutating any target" {
    run bash -c "${alignment_child}"'
        lemper_load_module runtime/site/commands
        . "$REAL_BASE_DIR/lib/services/nginx/site.sh"
        lemper_nginx_site_snapshot() { [[ "$1" != second.example.com ]]; }
        lemper_legacy_site_action() { echo MUTATED; }
        lemper_site_change update example.com second.example.com --cors-enable
    '
    [ "$status" -ne 0 ]
    [[ "$output" != *MUTATED* ]]
}

@test "removing one PHP branch keeps shared libraries when another branch remains" {
    run bash -c "${alignment_child}"'
        LEMPER_PHP_REMOVAL_LIB_ONLY=true
        run() { printf "RUN:%s\n" "$*"; }
        . "$REAL_BASE_DIR/scripts/remove_php.sh"
        AUTO_REMOVE=true
        PHP_VERSIONS=8.1
        remove_php() { echo "REMOVED:$1"; }
        dpkg-query() { printf "php8.5-fpm\tinstall ok installed\n"; }
        init_php_removal --php-version 8.1
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *REMOVED:8.1* ]]
    [[ "$output" != *"/usr/lib/php"* ]]
    [[ "$output" != *"purge"* ]]
    [[ "$output" != *"ondrej/php"* ]]
}
@test "PHP removal package selection excludes other branches and config-only packages" {
    run bash -c "${alignment_child}"'
        LEMPER_PHP_REMOVAL_LIB_ONLY=true
        run() { :; }
        . "$REAL_BASE_DIR/scripts/remove_php.sh"
        dpkg-query() {
            printf "php8.1-fpm\tinstall ok installed\nphp8.10-fpm\tinstall ok installed\nphp8.1-curl\tdeinstall ok config-files\n"
        }
        php_removal_packages 8.1
    '
    [ "$status" -eq 0 ]
    [ "$output" = php8.1-fpm ]
}
