#!/usr/bin/env bats
load env_helper
setup() {
    unit_setup
    export LEMPER_NGINX_DIR="$TEST_TMPDIR/nginx"
    export LEMPER_PHP_DIR="$TEST_TMPDIR/php"
    export LEMPER_SITE_STATE_DIR="$TEST_TMPDIR/sites"
    export LEMPER_SITE_APP_STATE_DIR="$TEST_TMPDIR/apps-state"
    export LEMPER_OPERATION_LOCK="$TEST_TMPDIR/operation.lock"
    mkdir -p "$LEMPER_NGINX_DIR"/sites-{available,enabled} "$LEMPER_SITE_STATE_DIR" \
        "$LEMPER_PHP_DIR/8.3/fpm/pool.d" "$TEST_TMPDIR/parent" "$TEST_TMPDIR/project one/public" "$TEST_TMPDIR/project2/public"
    chown www-data "$TEST_TMPDIR/parent" "$TEST_TMPDIR/project one" "$TEST_TMPDIR/project2"
    printf '<?php echo "fixture";\n' > "$TEST_TMPDIR/project one/public/index.php"
    cp "$TEST_TMPDIR/project one/public/index.php" "$TEST_TMPDIR/project2/public/index.php"
    printf '[www]\nuser = www-data\nlisten = /run/php/php8.3-fpm.sock\n' > "$LEMPER_PHP_DIR/8.3/fpm/pool.d/www.conf"
    printf 'server {\n    root "%s/parent";\n    location / { try_files $uri =404; }\n}\n' "$TEST_TMPDIR" > "$LEMPER_NGINX_DIR/sites-available/example.test.conf"
    printf 'OWNER_MARKER=lemper-site-v1\nDOMAIN=example.test\nOWNER=www-data\nWEBROOT=%s/parent\nRUNTIME=php@8.3\nDATABASE=\n' "$TEST_TMPDIR" > "$LEMPER_SITE_STATE_DIR/example.test.conf"
}
# shellcheck disable=SC2016 # Fixed code; services are stubbed and paths are isolated.
app_child='
 . "$REAL_BASE_DIR/lib/core/loader.sh"
 . "$REAL_BASE_DIR/lib/runtime/site/commands.sh"
 . "$REAL_BASE_DIR/lib/runtime/site/state.sh"
 . "$REAL_BASE_DIR/lib/runtime/site/apps.sh"
 . "$REAL_BASE_DIR/lib/services/nginx/site.sh"
 . "$REAL_BASE_DIR/lib/services/nginx/apps.sh"
 . "$REAL_BASE_DIR/lib/services/php/lifecycle.sh"
 error() { printf "%s\n" "$*" >&2; }
 info() { printf "%s\n" "$*"; }
 success() { printf "%s\n" "$*"; }
 lemper_nginx_site_reload() { echo RELOAD; }
'
@test "app help is public and default/runtime/app modules are source-only" {
    run test_run_public "$REAL_BASE_DIR" bin/lemper-cli.sh site app add --help
    [ "$status" -eq 0 ]
    [[ "$output" == *'--mount'* ]]
    run bash -c 'for f in "$1/lib/runtime/stack/config.sh" "$1/lib/services/php/defaults.sh" "$1/lib/core/config-update.sh" "$1/lib/runtime/site/apps.sh" "$1/lib/services/nginx/apps.sh"; do . "$f" || exit 1; done; echo SOURCED' _ "$REAL_BASE_DIR"
    [ "$status" -eq 0 ]
    [ "$output" = SOURCED ]
}
@test "adding and updating an app preserves its parent and stores independent ownership" {
    run bash -c "${app_child}"'
      init_lemper_site_app add example.test --mount /demo --webroot "$TEST_TMPDIR/project one" || exit 1
      init_lemper_site_app list example.test || exit 1
      init_lemper_site_app update example.test --mount /demo --webroot "$TEST_TMPDIR/project2" || exit 1
      init_lemper_site_app list example.test
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *'/demo'*'php@8.3'*'www-data'* ]]
    grep -Fq "$TEST_TMPDIR/project2/public/index.php" "$LEMPER_NGINX_DIR/site-apps/example.test/demo.conf"
    [ "$(stat -c %a "$LEMPER_SITE_APP_STATE_DIR/example.test/demo.conf")" = 600 ]
    [ "$(stat -c %a "$LEMPER_NGINX_DIR/site-apps/example.test/demo.conf")" = 644 ]
    [ "$(grep -c 'site-apps/example.test' "$LEMPER_NGINX_DIR/sites-available/example.test.conf")" -eq 1 ]
    grep -Fq "$TEST_TMPDIR/parent" "$LEMPER_NGINX_DIR/sites-available/example.test.conf"
}
@test "invalid URL prefixes, injection, unknown types, and absent FPM pools fail before publication" {
    run bash -c "${app_child}"'
      for mount in /../escape /demo/nested /lcp /php-fpm_status /demo\;bad; do
        init_lemper_site_app add example.test --mount "$mount" --webroot "$TEST_TMPDIR/project one" --dry-run && exit 1
      done
      init_lemper_site_app add example.test --mount /demo --webroot "$TEST_TMPDIR/project one" --runtime=php@8.1 --dry-run && exit 1
      init_lemper_site_app add example.test --mount /demo --webroot "$TEST_TMPDIR/project one" --type=wordpress --dry-run && exit 1
      init_lemper_site_app add example.test --mount /demo --webroot "$TEST_TMPDIR/project one" --runtime=php@8.4 --dry-run && exit 1
      init_lemper_site_app add example.test --mount /demo --webroot "$TEST_TMPDIR/project one" --runtime-user=root --dry-run && exit 1
      exit 0
    '
    [ "$status" -eq 0 ]
    [ ! -d "$LEMPER_NGINX_DIR/site-apps" ]
}
@test "dry run creates no lock, state, hook, or fragment and rejects unmanaged parent sites" {
    local before
    before=$(sha256sum "$LEMPER_NGINX_DIR/sites-available/example.test.conf")
    run bash -c "${app_child}"'
      init_lemper_site_app add example.test --mount /demo --webroot "$TEST_TMPDIR/project one" --dry-run || exit 1
      rm "$LEMPER_SITE_STATE_DIR/example.test.conf"
      init_lemper_site_app add example.test --mount /demo --webroot "$TEST_TMPDIR/project one" --dry-run && exit 1
      exit 0
    '
    [ "$status" -eq 0 ]
    [ "$before" = "$(sha256sum "$LEMPER_NGINX_DIR/sites-available/example.test.conf")" ]
    [ ! -e "$LEMPER_OPERATION_LOCK" ]
    [ ! -e "$LEMPER_NGINX_DIR/site-apps" ]
}
@test "reload failure restores parent SSL variants, fragment, and application metadata" {
    run bash -c "${app_child}"'
      init_lemper_site_app add example.test --mount /demo --webroot "$TEST_TMPDIR/project one" || exit 1
      cp "$LEMPER_NGINX_DIR/sites-available/example.test.conf" "$LEMPER_NGINX_DIR/sites-available/example.test.ssl-conf"
      cp "$LEMPER_NGINX_DIR/sites-available/example.test.conf" "$LEMPER_NGINX_DIR/sites-available/example.test.nonssl-conf"
      rm "$LEMPER_NGINX_DIR/sites-available/example.test.conf"
      ln -s "$LEMPER_NGINX_DIR/sites-available/example.test.ssl-conf" "$LEMPER_NGINX_DIR/sites-available/example.test.conf"
      before=$(sha256sum "$LEMPER_NGINX_DIR/site-apps/example.test/demo.conf" "$LEMPER_SITE_APP_STATE_DIR/example.test/demo.conf" "$LEMPER_NGINX_DIR/sites-available/example.test."{ssl-conf,nonssl-conf})
      lemper_nginx_site_reload() { return 1; }
      init_lemper_site_app update example.test --mount /demo --webroot "$TEST_TMPDIR/project2" && exit 1
      [[ "$before" == "$(sha256sum "$LEMPER_NGINX_DIR/site-apps/example.test/demo.conf" "$LEMPER_SITE_APP_STATE_DIR/example.test/demo.conf" "$LEMPER_NGINX_DIR/sites-available/example.test."{ssl-conf,nonssl-conf})" ]]
    '
    [ "$status" -eq 0 ]
    [ -L "$LEMPER_NGINX_DIR/sites-available/example.test.conf" ]
}
@test "app removal retains project data and permits cleanup after the parent is unregistered" {
    run bash -c "${app_child}"'
      init_lemper_site_app add example.test --mount /demo --webroot "$TEST_TMPDIR/project one" || exit 1
      rm "$LEMPER_NGINX_DIR/sites-available/example.test.conf"
      init_lemper_site_app remove example.test --mount /demo --yes
    '
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/project one/public/index.php" ]
    [ ! -f "$LEMPER_NGINX_DIR/site-apps/example.test/demo.conf" ]
    [ ! -f "$LEMPER_SITE_APP_STATE_DIR/example.test/demo.conf" ]
}
@test "PHP removal and parent purge reject references in mounted applications" {
    run bash -c "${app_child}"'
      init_lemper_site_app add example.test --mount /demo --webroot "$TEST_TMPDIR/project one" || exit 1
      lemper_php_check_references 8.3 && exit 1
      lemper_site_purge_preflight example.test && exit 1
      init_lemper_site_app remove example.test --mount /demo --yes || exit 1
      lemper_php_check_references 8.3
    '
    [ "$status" -eq 0 ]
}
@test "unknown vhost layouts are restored rather than accepting an unsafe include insertion" {
    printf 'server { root /custom; }\n' > "$LEMPER_NGINX_DIR/sites-available/example.test.conf"
    run bash -c "${app_child}"'init_lemper_site_app add example.test --mount /demo --webroot "$TEST_TMPDIR/project one"'
    [ "$status" -ne 0 ]
    [ "$(cat "$LEMPER_NGINX_DIR/sites-available/example.test.conf")" = 'server { root /custom; }' ]
    [ ! -f "$LEMPER_NGINX_DIR/site-apps/example.test/demo.conf" ]
}

@test "mounts refuse sibling location authentication while preserving inherited server policies" {
    run bash -c "${app_child}"'
      printf "server {\n    root \\\"%s/parent\\\";\n    location / { auth_basic private; }\n}\n" "$TEST_TMPDIR" > "$LEMPER_NGINX_DIR/sites-available/example.test.conf"
      init_lemper_site_app add example.test --mount /demo --webroot "$TEST_TMPDIR/project one" --dry-run && exit 1
      printf "server {\n    root \\\"%s/parent\\\";\n    auth_basic private;\n    location / { try_files \\\$uri =404; }\n}\n" "$TEST_TMPDIR" > "$LEMPER_NGINX_DIR/sites-available/example.test.conf"
      init_lemper_site_app add example.test --mount /demo --webroot "$TEST_TMPDIR/project one" --dry-run
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *'Per-location access controls'* ]]
    [ ! -f "$LEMPER_NGINX_DIR/site-apps/example.test/demo.conf" ]
}
