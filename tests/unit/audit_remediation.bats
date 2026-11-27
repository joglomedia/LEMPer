#!/usr/bin/env bats
load env_helper

setup() {
    unit_setup
    . "$REAL_BASE_DIR/lib/core/security.sh"
    . "$REAL_BASE_DIR/lib/core/execution.sh"
    error() { printf '%s\n' "$*" >&2; }
    info() { :; }
}

@test "database grant helper quotes each literal schema underscore" {
    . "$REAL_BASE_DIR/lib/services/mariadb/database.sh"
    [ "$(lemper_db_grant_schema app_2026_main)" = 'app\_2026\_main' ]
    [ "$(lemper_db_grant_schema app)" = app ]
    run lemper_db_grant_schema ''
    [ "$status" -ne 0 ]
}

@test "new hosting credentials are independent and RNG failure stops before user creation" {
    . "$REAL_BASE_DIR/lib/services/accounts/user.sh"
    LEMPER_PASSWORD=fixture-bootstrap
    getent() { return 2; }
    useradd() { touch "$TEST_TMPDIR/useradd"; return 1; }
    # Stop immediately before account mutation and compare only digests.
    remove_managed_account_sudo() {
        printf '%s' "$PASSWORD" | sha256sum >> "$TEST_TMPDIR/credentials"
        return 1
    }
    run create_account fixtureone
    [ "$status" -ne 0 ]
    run create_account fixturetwo
    [ "$status" -ne 0 ]
    [ "$(sort -u "$TEST_TMPDIR/credentials" | wc -l)" -eq 2 ]
    openssl() { return 1; }
    run create_account fixturethree
    [ "$status" -ne 0 ]
    [ "$(wc -l < "$TEST_TMPDIR/credentials")" -eq 2 ]
    [ ! -e "$TEST_TMPDIR/useradd" ]
}

@test "account deprovisioning only removes its marked sudo rule" {
    . "$REAL_BASE_DIR/lib/core/accounts.sh"
    printf '# local operator rule\n' > "$TEST_TMPDIR/90-fixture"
    remove_managed_account_sudo fixture "$TEST_TMPDIR"
    [ -f "$TEST_TMPDIR/90-fixture" ]
    printf '# LEMPer-managed restricted administrator: fixture\n' > "$TEST_TMPDIR/90-fixture"
    DRYRUN=true run remove_managed_account_sudo fixture "$TEST_TMPDIR"
    [ "$status" -eq 0 ] && [ -f "$TEST_TMPDIR/90-fixture" ]
    remove_managed_account_sudo fixture "$TEST_TMPDIR"
    [ ! -e "$TEST_TMPDIR/90-fixture" ]
}

@test "dispatcher decrypts configuration from stdin and handles an incorrect key privately" {
    [ "$EUID" -eq 0 ] || skip "dispatcher requires root in a disposable Linux fixture"
    local cli="$REAL_BASE_DIR/bin/lemper-cli.sh"
    export LEMPER_CONFIG_FILE="$TEST_TMPDIR/encrypted"
    openssl enc -aes-256-cbc -a -salt -md sha256 -pbkdf2 -pass fd:3 3<<<fixture-config-key \
        -in "$REAL_BASE_DIR/.env.dist" -out "$LEMPER_CONFIG_FILE"
    run bash "$cli" config check --config-password-stdin <<<fixture-config-key
    [ "$status" -eq 0 ] && [[ "$output" == *"schema valid"* && "$output" != *fixture-config-key* ]]
    . "$REAL_BASE_DIR/lib/core/config.sh"
    . "$REAL_BASE_DIR/lib/services/tools/update.sh"
    LEMPER_CONFIG_PASSWORD=fixture-config-key tools_decrypt_config "$LEMPER_CONFIG_FILE" "$TEST_TMPDIR/private"
    cmp "$TEST_TMPDIR/private" "$REAL_BASE_DIR/.env.dist"
    run bash "$cli" config check --config-password-stdin <<<incorrect-fixture-key
    [ "$status" -ne 0 ] && [[ "$output" != *incorrect-fixture-key* ]]
    run bash "$cli" config check --password=legacy-fixture-key
    [ "$status" -ne 0 ] && [[ "$output" == *"--config-password-stdin"* && "$output" != *legacy-fixture-key* ]]
}

@test "lock and disk probe reject shared or linked parents and keep a trusted probe temporary" {
    . "$REAL_BASE_DIR/lib/services/system/benchmark.sh"
    mkdir "$TEST_TMPDIR/trusted" "$TEST_TMPDIR/shared"
    chmod 0777 "$TEST_TMPDIR/shared"
    ln -s "$TEST_TMPDIR/trusted" "$TEST_TMPDIR/alias"
    for parent in "$TEST_TMPDIR/shared" "$TEST_TMPDIR/alias"; do
        run bench_disk_probe 1 "$parent"
        [ "$status" -ne 0 ]
        run lemper_lock_path "$parent/lock"
        [ "$status" -ne 0 ]
    done
    run bench_disk_probe 1 "$TEST_TMPDIR/trusted"
    [ "$status" -eq 0 ] && [[ "$output" == *'write|'* ]]
    [ -z "$(ls -A "$TEST_TMPDIR/trusted")" ]
    run lemper_with_lock umask
    [ "$status" -eq 0 ] && [ "$output" = "$(umask)" ]
    [ "$(stat -c %a "$LEMPER_OPERATION_LOCK")" = 600 ]
}

@test "public address rendering validates HTTPS replies and falls back when unavailable" {
    . "$REAL_BASE_DIR/lib/core/network.sh"
    . "$REAL_BASE_DIR/lib/core/validation.sh"
    curl() { [[ "$1" == -q && " $* " == *" --proto =https "* ]] || return 1; printf '%s' "$reply"; }
    reply='192.0.2.1'
    [ "$(core_get_ip)" = "$reply" ]
    reply='2001:db8::1'
    [ "$(core_get_ipv6_public)" = "$reply" ]
    reply='invalid response'
    get_ip_private() { printf '%s' 10.0.0.1; }
    [ "$(core_get_ip)" = 10.0.0.1 ]
    curl() { return 1; }
    get_ip_private() { return 1; }
    [ "$(core_get_ip)" = 127.0.0.1 ]
}

@test "privileged web tool refresh accepts internal program links and checks tree ownership" {
    [ "$EUID" -eq 0 ] || skip "tests ownership of a root-managed tree"
    local tree="$TEST_TMPDIR/html"
    mkdir -p "$tree/vendor/bin" "$tree/vendor/tool"
    touch "$tree/vendor/tool/cli"
    ln -s ../tool/cli "$tree/vendor/bin/cli"
    lemper_web_tools_tree_safe "$tree"
    chmod 0666 "$tree/vendor/tool/cli"
    run lemper_web_tools_tree_safe "$tree"
    [ "$status" -ne 0 ]
    chmod 0644 "$tree/vendor/tool/cli"
    ln -s "$TEST_TMPDIR" "$tree/other"
    run lemper_web_tools_tree_safe "$tree"
    [ "$status" -ne 0 ]
}

@test "Redis panel refresh updates only a recognized config and protects credential bytes" {
    [ "$EUID" -eq 0 ] || skip "sets the PHP worker group on its private config"
    . "$REAL_BASE_DIR/lib/services/tools/install.sh"
    local config="$TEST_TMPDIR/config.php" sample="$TEST_TMPDIR/sample.php"
    printf '%s\n' "<?php return [" "  //'auth' => 'redispasswordhere'" '];' > "$sample"
    cp "$sample" "$config"
    REDIS_PASSWORD='fixture pass'
    run lemper_redis_panel_auth "$config" "$sample"
    [ "$status" -eq 0 ] && [[ "$output" != *"$REDIS_PASSWORD"* ]]
    [ "$(stat -c %a:%G "$config")" = 640:www-data ]
    grep -Fq "hex2bin('666978747572652070617373')" "$config"
    REDIS_PASSWORD='new'
    lemper_redis_panel_auth "$config" "$sample"
    grep -Fq "hex2bin('6e6577')" "$config"
    printf '// customized\n' >> "$config"
    cp "$config" "$TEST_TMPDIR/expected"
    REDIS_PASSWORD='another' lemper_redis_panel_auth "$config" "$sample"
    cmp -s "$config" "$TEST_TMPDIR/expected"
}
