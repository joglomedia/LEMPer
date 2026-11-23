#!/usr/bin/env bats
# shellcheck disable=SC2016 # Fixed child shell programs retain literal expansions.
# shellcheck disable=SC2030,SC2031 # Bats isolates each wizard fixture and its selected option.
load env_helper
setup() {
    unit_setup
    export LEMPER_NGINX_DIR="$TEST_TMPDIR/nginx"
    export LEMPER_SITE_STATE_DIR="$TEST_TMPDIR/state"
    export TEST_APP_LOG="$TEST_TMPDIR/app.log" TEST_PROMPTS="$TEST_TMPDIR/prompts"
    mkdir -p "$LEMPER_NGINX_DIR/sites-available" "$LEMPER_NGINX_DIR/sites-enabled"
}
app_child='
    . "$REAL_BASE_DIR/lib/core/loader.sh"
    lemper_load_module services/site/applications
    lemper_load_module runtime/site/commands
    . "$REAL_BASE_DIR/lib/services/nginx/site.sh"
    . "$REAL_BASE_DIR/lib/runtime/site/state.sh"
    error() { printf "%s\n" "$*" >&2; }
    info() { printf "%s\n" "$*"; }
'
@test "unsupported app installation rejects modern and legacy aliases before locks, directories or dispatch" {
    local type flag
    for type in sendy default; do
        for flag in --install-skeleton --install-app -i; do
            run bash -c "$app_child"'
                lemper_legacy_site_create() { echo MUTATION; }
                lemper_site_create example.test --type="$1" --runtime-user=root --webroot="$TEST_TMPDIR/project" "$2"
            ' _ "$type" "$flag"
            [ "$status" -ne 0 ]
            [[ "$output" == *'omit --install-skeleton/--install-app'* ]]
            [[ "$output" != *MUTATION* ]]
        done
    done
    [ ! -e "$LEMPER_OPERATION_LOCK" ]
    [ ! -e "$LEMPER_NGINX_DIR/site-apps" ]
    [ ! -e "$TEST_TMPDIR/project" ]
}
@test "dry-run rejects unavailable skeletons and unknown types while manual vhost requests remain valid" {
    local type
    for type in mautic roundcube sendy; do
        run bash -c "$app_child"'lemper_site_create example.test --type="$1" --runtime-user=lemper --install-skeleton --dry-run' _ "$type"
        if [[ "$type" == sendy ]]; then [ "$status" -ne 0 ]; else [ "$status" -eq 0 ]; fi
        run bash -c "$app_child"'lemper_site_create example.test --type="$1" --dry-run' _ "$type"
        [ "$status" -eq 0 ]
        [[ "$output" == *'Would create example.test'* ]]
    done
    run bash -c "$app_child"'lemper_site_create example.test --type=unknown --dry-run'
    [ "$status" -ne 0 ]
}
@test "direct legacy create rejects unsupported installation before package checks and host initialization" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module runtime/site/create
        error() { printf "%s\n" "$*" >&2; }
        check_required_packages() { echo PACKAGE_CHECK; return 1; }
        lemper_site_create_command -d example.test -f sendy -i
    '
    [ "$status" -ne 0 ]
    [[ "$output" != *PACKAGE_CHECK* ]]
    [[ "$output" == *'Automatic Sendy installation is unavailable'* ]]
}
@test "successful installer dispatch with only a placeholder cannot publish site ownership" {
    run bash -c "$app_child"'
        lemper_legacy_site_create() {
            mkdir -p "$TEST_TMPDIR/project"
            printf "placeholder" > "$TEST_TMPDIR/project/index.html"
            printf "server { root %s/project; }\n" "$TEST_TMPDIR" > "$LEMPER_NGINX_DIR/sites-available/example.test.conf"
        }
        nginx() { :; }
        lemper_site_create example.test --type=wordpress --runtime-user=root --install-skeleton --webroot="$TEST_TMPDIR/project"
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *'did not produce the expected application files'* ]]
    [ ! -e "$LEMPER_SITE_STATE_DIR/example.test.conf" ]
}
@test "actual supported project files satisfy the install contract and permit ownership recording" {
    run bash -c "$app_child"'
        lemper_legacy_site_create() {
            mkdir -p "$TEST_TMPDIR/project/public"
            printf "<?php // Laravel CLI\n" > "$TEST_TMPDIR/project/artisan"
            printf "<?php // Laravel HTTP entry\n" > "$TEST_TMPDIR/project/public/index.php"
            printf "server {\n root %s/project/public;\n}\n" "$TEST_TMPDIR" > "$LEMPER_NGINX_DIR/sites-available/example.test.conf"
        }
        nginx() { :; }
        lemper_site_create example.test --type=laravel --runtime-user=root --install-skeleton --webroot="$TEST_TMPDIR/project"
    '
    [ "$status" -eq 0 ]
    [ -f "$LEMPER_SITE_STATE_DIR/example.test.conf" ]
    grep -qx "WEBROOT=$TEST_TMPDIR/project/public" "$LEMPER_SITE_STATE_DIR/example.test.conf"
}
@test "empty or unrelated application markers do not satisfy the selected framework" {
    mkdir -p "$TEST_TMPDIR/project/public"
    printf '<?php\n' > "$TEST_TMPDIR/project/public/index.php"
    touch "$TEST_TMPDIR/project/artisan"
    run bash -c "$app_child"'lemper_site_application_check_files laravel "$TEST_TMPDIR/project"'
    [ "$status" -ne 0 ]
    run bash -c "$app_child"'lemper_site_application_check_files wordpress "$TEST_TMPDIR/project"'
    [ "$status" -ne 0 ]
}
@test "generic PHP entry files cannot satisfy any automatic application contract" {
    mkdir -p "$TEST_TMPDIR/project/public"
    printf '<?php echo "placeholder";\n' > "$TEST_TMPDIR/project/index.php"
    cp "$TEST_TMPDIR/project/index.php" "$TEST_TMPDIR/project/public/index.php"
    run bash -c "$app_child"'
        while IFS="|" read -r id label capability wizard markers; do
            [[ "$capability" == automatic ]] || continue
            if lemper_site_application_check_files "$id" "$TEST_TMPDIR/project"; then
                echo "Generic placeholder accepted for $id"
                exit 1
            fi
        done < <(lemper_site_application_registry)
    '
    [ "$status" -eq 0 ]
}
wizard_exec() {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module runtime/tui/commands
        tui_clear() { :; }
        tui_echo() { :; }
        tui_menu() { printf "%s\n" "$1" "$2" "${@:3}" > "$TEST_APP_LOG"; echo "$TEST_SELECTION"; }
        tui_default_php_version() { echo 8.5; }
        tui_confirm() {
            printf "%s\n" "$1" >> "$TEST_PROMPTS"
            case "$1" in "Install "*|"Create this site now?") return 0 ;; *) return 1 ;; esac
        }
        tui_cli() { printf "<%s>\n" "$@" > "$TEST_TMPDIR/command"; }
        tui_site_create_wizard < "$TEST_TMPDIR/answers"
    '
}
@test "TUI keeps manual app types selectable without an installation prompt or install flag" {
    printf 'example.test\nroot\n%s/project\n8.5\n\n' "$TEST_TMPDIR" > "$TEST_TMPDIR/answers"
    local selection
    for selection in 1 11; do
        export TEST_SELECTION="$selection"
        wizard_exec
        [ "$status" -eq 0 ]
        run grep -q '^Install ' "$TEST_PROMPTS"
        [ "$status" -eq 1 ]
        run grep -q '<--install-app>' "$TEST_TMPDIR/command"
        [ "$status" -eq 1 ]
    done
    grep -q 'Vhost setup; deploy application files manually' "$TEST_APP_LOG"
}
@test "TUI offers supported skeleton installation and forwards the user's choice to the same CLI" {
    printf 'example.test\nroot\n%s/project\n8.5\n\n' "$TEST_TMPDIR" > "$TEST_TMPDIR/answers"
    export TEST_SELECTION=2
    wizard_exec
    [ "$status" -eq 0 ]
    grep -qx 'Install wordpress application files?' "$TEST_PROMPTS"
    grep -qx '<--install-app>' "$TEST_TMPDIR/command"
    grep -qx '<--framework=wordpress>' "$TEST_TMPDIR/command"
}
@test "Mautic and Roundcube accept all installation aliases in dry-run and offer them in the wizard" {
    local type flag selection
    for type in mautic roundcube; do
        for flag in --install-skeleton --install-app -i; do
            run bash -c "$app_child"'lemper_site_create example.test --type="$1" --runtime-user=lemper --dry-run "$2"' _ "$type" "$flag"
            [ "$status" -eq 0 ]
        done
    done
    printf 'example.test\nroot\n%s/project\n8.5\n\n' "$TEST_TMPDIR" > "$TEST_TMPDIR/answers"
    for selection in 9 10; do
        export TEST_SELECTION="$selection"
        wizard_exec
        [ "$status" -eq 0 ]
        grep -qx '<--install-app>' "$TEST_TMPDIR/command"
    done
    grep -qx 'Install mautic application files?' "$TEST_PROMPTS"
    grep -qx 'Install roundcube application files?' "$TEST_PROMPTS"
    [ ! -e "$LEMPER_OPERATION_LOCK" ]
}
