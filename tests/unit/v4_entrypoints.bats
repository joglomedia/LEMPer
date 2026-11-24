#!/usr/bin/env bats
load env_helper
setup() {
    unit_setup
    export LEMPER_OPERATION_LOCK="$TEST_TMPDIR/lock"
    export LEMPER_INSTALLED_DIR="$TEST_TMPDIR/installed-components"
    mkdir -p "$LEMPER_INSTALLED_DIR"
    printf 'SSH_PASSWORDLESS=false\nSERVER_HOSTNAME=fixture.example.test\nSERVER_IP=127.0.0.1\n' > "$TEST_TMPDIR/profile"
}

@test "all compatibility entry points expose profile help without root or configuration" {
    local entry
    for entry in install.sh remove.sh update.sh lemper.sh; do
        run test_run_public "$REAL_BASE_DIR" "$entry" --help
        [ "$status" -eq 0 ]
        [[ "$output" == *"--config FILE"* ]]
    done
}

@test "canonical full-stack dry run validates before installed config loading and preserves the profile" {
    local before
    before=$(sha256sum "$TEST_TMPDIR/profile")
    run env -u BASE_DIR LEMPER_CONFIG_FILE="$TEST_TMPDIR/missing" \
        bash "$REAL_BASE_DIR/bin/lemper-cli.sh" stack install --all --config "$TEST_TMPDIR/profile" --minimal --yes --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"nginx"* && "$output" == *"mariadb"* && "$output" == *"fail2ban"* ]]
    [[ "$output" != *"  ftp"* && "$output" != *"  redis"* && "$output" != *"  imagemagick"* ]]
    [ "$(sha256sum "$TEST_TMPDIR/profile")" = "$before" ]
    [ ! -e "$LEMPER_OPERATION_LOCK" ]
}

@test "unattended full-stack validation rejects missing SSH keys even if the profile was interactive" {
    printf 'AUTO_INSTALL=false\nSSH_PASSWORDLESS=true\nRSA_PUB_KEY=\n' > "$TEST_TMPDIR/profile"
    run bash "$REAL_BASE_DIR/install.sh" --config "$TEST_TMPDIR/profile" --yes --check-config
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires a valid RSA_PUB_KEY"* ]]
    [ ! -e "$LEMPER_OPERATION_LOCK" ]
}

@test "full-stack routing rejects conflicting service operands and profile control-key injection" {
    run bash "$REAL_BASE_DIR/install.sh" --config= --dry-run
    [ "$status" -ne 0 ]
    run bash "$REAL_BASE_DIR/install.sh" --config "$TEST_TMPDIR/profile" --config "$TEST_TMPDIR/profile" --dry-run
    [ "$status" -ne 0 ]
    run bash "$REAL_BASE_DIR/bin/lemper-cli.sh" stack install nginx --all --config "$TEST_TMPDIR/profile" --dry-run
    [ "$status" -ne 0 ]
    printf 'LEMPER_INSTALL_ROOT=/tmp/injected\n' > "$TEST_TMPDIR/profile"
    run bash "$REAL_BASE_DIR/install.sh" --config "$TEST_TMPDIR/profile" --check-config
    [ "$status" -ne 0 ]
    [[ "$output" == *"Forbidden configuration key"* ]]
}

@test "minimal profile retains security choices while disabling optional services and web panels" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        . "$REAL_BASE_DIR/lib/runtime/stack/entry.sh"
        DRYRUN=false
        target=$(mktemp "$TEST_TMPDIR/effective.XXXXXXXX")
        lemper_entry_profile "$REAL_BASE_DIR" "$TEST_TMPDIR/profile" "$target" install true true || exit 1
        grep -qx INSTALL_WEB_ADMIN=false "$target" || exit 1
        grep -qx INSTALL_FTP_SERVER=false "$target" || exit 1
        grep -qx INSTALL_FAIL2BAN=true "$target" || exit 1
        grep -qx INSTALL_FW=true "$target" || exit 1
        grep -qx SSH_PASSWORDLESS=false "$target" || exit 1
        [ "$(stat -c %a "$target")" = 600 ]
    '
    [ "$status" -eq 0 ]
}

@test "explicit install profiles preserve generated credentials while reconciling service flags" {
    printf 'MYSQL_ROOT_PASSWORD=synthetic-existing\nINSTALL_WEB_ADMIN=true\n' > "$TEST_TMPDIR/installed"
    printf 'MYSQL_ROOT_PASSWORD=\nSSH_PASSWORDLESS=false\n' > "$TEST_TMPDIR/profile"
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        . "$REAL_BASE_DIR/lib/runtime/stack/entry.sh"
        DRYRUN=false
        target=$(mktemp "$TEST_TMPDIR/effective.XXXXXXXX")
        lemper_entry_profile "$REAL_BASE_DIR" "$TEST_TMPDIR/profile" "$target" install true true "$TEST_TMPDIR/installed" || exit 1
        grep -qx MYSQL_ROOT_PASSWORD=synthetic-existing "$target" || exit 1
        grep -qx INSTALL_WEB_ADMIN=false "$target"
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *synthetic-existing* ]]
}

@test "profile-level dry run does not create the operation lock" {
    printf 'DRYRUN=true\nSSH_PASSWORDLESS=false\n' > "$TEST_TMPDIR/profile"
    run bash "$REAL_BASE_DIR/install.sh" --config "$TEST_TMPDIR/profile" --minimal --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"no system changes"* ]]
    [ ! -e "$LEMPER_OPERATION_LOCK" ]
}

@test "explicit profile storage honors custom encryption and preserves config on replacement failure" {
    UAT_STATE="$TEST_TMPDIR/state" awk '{gsub(/\/etc\/lemper/,ENVIRON["UAT_STATE"]); print}' \
        "$REAL_BASE_DIR/lib/core/config.sh" >"$TEST_TMPDIR/config.sh"
    printf 'SSH_PASSWORDLESS=false\nINSTALL_WEB_ADMIN=false\n' > "$TEST_TMPDIR/profile"
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        . "$TEST_TMPDIR/config.sh"
        success() { :; }
        save_log() { :; }
        ENVFILE="$TEST_TMPDIR/profile"
        DRYRUN=false ENCRYPT_CONFIG_AT_REST=true
        LEMPER_CONFIG_PASSWORD=synthetic-custom
        core_store_install_profile "$ENVFILE" || exit 1
        openssl enc -aes-256-cbc -d -a -salt -md sha256 -pbkdf2 -pass fd:3 3<<<"$LEMPER_CONFIG_PASSWORD" \
            -in "$TEST_TMPDIR/state/lemper.conf" -out "$TEST_TMPDIR/decoded" || exit 1
        grep -qx INSTALL_WEB_ADMIN=false "$TEST_TMPDIR/decoded" || exit 1
        before=$(sha256sum "$TEST_TMPDIR/state/lemper.conf")
        mv() { return 1; }
        ! core_store_install_profile "$ENVFILE" || exit 1
        [ "$(sha256sum "$TEST_TMPDIR/state/lemper.conf")" = "$before" ] || exit 1
        [ -z "$(find "$TEST_TMPDIR/state" -name ".install-profile.*" -print)" ]
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *synthetic-custom* ]]
}

@test "installation recipes do not source disabled components" {
    mkdir -p "$TEST_TMPDIR/source/scripts" "$TEST_TMPDIR/source/lib/core"
    cp "$REAL_BASE_DIR/lib/core/registry.sh" "$TEST_TMPDIR/source/lib/core/"
    printf 'echo NGINX_ENABLED\n' > "$TEST_TMPDIR/source/scripts/install_nginx.sh"
    printf 'echo CLI_ENABLED\n' > "$TEST_TMPDIR/source/scripts/install_tools.sh"
    printf 'echo DISABLED_COMPONENT_RAN; return 9\n' > "$TEST_TMPDIR/source/scripts/install_certbotle.sh"
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        . "$REAL_BASE_DIR/lib/runtime/stack/recipe.sh"
        BASE_DIR="$TEST_TMPDIR/source"
        INSTALL_NGINX=true
        INSTALL_PHP=false INSTALL_PHP_PHALCON=false INSTALL_MYSQL=false
        INSTALL_POSTGRES=false INSTALL_REDIS=false INSTALL_MONGODB=false
        INSTALL_MEMCACHED=false INSTALL_IMAGEMAGICK=false INSTALL_MAILER=false
        INSTALL_FTP_SERVER=false INSTALL_FAIL2BAN=false INSTALL_CROWDSEC=false
        INSTALL_MODSEC=false INSTALL_BUNJS=false INSTALL_CERTBOT=false
        lemper_recipe_components install
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *NGINX_ENABLED* && "$output" == *CLI_ENABLED* ]]
    [[ "$output" != *DISABLED_COMPONENT_RAN* ]]
}

@test "update compatibility entry normalizes source paths and excludes profile options from the updater" {
    mkdir -p "$TEST_TMPDIR/source/lib/compat"
    cp "$REAL_BASE_DIR/.env.dist" "$TEST_TMPDIR/source/.env.dist"
    ln -s "$REAL_BASE_DIR/lib/core" "$TEST_TMPDIR/source/lib/core"
    cat > "$TEST_TMPDIR/source/lib/compat/updater.sh" <<'SCRIPT'
#!/usr/bin/env bash
test -r "$LEMPER_CONFIG_FILE" || exit 1
printf '<%s>\n' "$@"
SCRIPT
    run bash -c '
        . "$REAL_BASE_DIR/lib/runtime/stack/entry.sh"
        LEMPER_ROOT="$TEST_TMPDIR/source"
        lemper_entry_main update --config "$TEST_TMPDIR/profile" --source-dir "/tmp/a path" --check --yes
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"<--source-dir=/tmp/a path>"* && "$output" == *"<--check>"* && "$output" == *"<--yes>"* ]]
    [[ "$output" != *"<--config>"* ]]
}

@test "full removal skips unowned components before sourcing any remover" {
    mkdir -p "$TEST_TMPDIR/source/scripts" "$TEST_TMPDIR/source/lib/core"
    cp "$REAL_BASE_DIR/lib/core/registry.sh" "$TEST_TMPDIR/source/lib/core/"
    printf 'echo OWNED_NGINX\n' > "$TEST_TMPDIR/source/scripts/remove_nginx.sh"
    printf 'echo UNOWNED_POSTGRES_RAN; return 9\n' > "$TEST_TMPDIR/source/scripts/remove_postgres.sh"
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        . "$REAL_BASE_DIR/lib/runtime/stack/recipe.sh"
        BASE_DIR="$TEST_TMPDIR/source"
        FORCE_REMOVE=false
        PHP_VERSIONS="8.4 8.5"
        lemper_provisioned() { [[ "$1" == nginx ]]; }
        mark_lemper_provisioned() { :; }
        lemper_recipe_components remove
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *OWNED_NGINX* && "$output" != *UNOWNED_POSTGRES_RAN* ]]
}

@test "full removal selects every owned PHP version instead of only the configured default" {
    mkdir -p "$TEST_TMPDIR/source/scripts" "$TEST_TMPDIR/source/lib/core"
    cp "$REAL_BASE_DIR/lib/core/registry.sh" "$TEST_TMPDIR/source/lib/core/"
    touch "$LEMPER_INSTALLED_DIR/php-8.4" "$LEMPER_INSTALLED_DIR/php-8.5"
    printf 'printf "VERSIONS=%%s\\n" "$PHP_VERSIONS"\n' > "$TEST_TMPDIR/source/scripts/remove_php.sh"
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        . "$REAL_BASE_DIR/lib/runtime/stack/recipe.sh"
        BASE_DIR="$TEST_TMPDIR/source"
        FORCE_REMOVE=false
        PHP_VERSIONS=8.5
        lemper_provisioned() { return 1; }
        lemper_recipe_components remove
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"VERSIONS= 8.4 8.5"* ]]
}

@test "failed full removal retains nginx ownership so teardown can be resumed" {
    mkdir -p "$TEST_TMPDIR/source/scripts" "$TEST_TMPDIR/source/lib/core"
    cp "$REAL_BASE_DIR/lib/core/registry.sh" "$TEST_TMPDIR/source/lib/core/"
    touch "$LEMPER_INSTALLED_DIR/nginx" "$LEMPER_INSTALLED_DIR/php-8.5"
    printf 'rm -f "$LEMPER_INSTALLED_DIR/nginx"\n' > "$TEST_TMPDIR/source/scripts/remove_nginx.sh"
    printf 'return 9\n' > "$TEST_TMPDIR/source/scripts/remove_php.sh"
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        . "$REAL_BASE_DIR/lib/runtime/stack/recipe.sh"
        BASE_DIR="$TEST_TMPDIR/source"
        FORCE_REMOVE=false
        lemper_provisioned() { [[ -f "$LEMPER_INSTALLED_DIR/$1" ]]; }
        mark_lemper_provisioned() { touch "$LEMPER_INSTALLED_DIR/$1"; }
        systemctl() { return 1; }
        pgrep() { return 1; }
        lemper_recipe_components remove
    '
    [ "$status" -ne 0 ]
    [ -f "$LEMPER_INSTALLED_DIR/nginx" ]
}
