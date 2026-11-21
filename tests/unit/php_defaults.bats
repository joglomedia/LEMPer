#!/usr/bin/env bats
load env_helper
setup() {
    unit_setup
    export CONFIG_FILE="$TEST_TMPDIR/profile"
    export LEMPER_OPERATION_LOCK="$TEST_TMPDIR/operation.lock"
    mkdir -p "$TEST_TMPDIR/bin" "$TEST_TMPDIR/alternatives"
    for group in php phar phar.phar; do
        for version in 8.3 8.4; do
            printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_TMPDIR/bin/$group$version"
            chmod 0755 "$TEST_TMPDIR/bin/$group$version"
        done
        printf 'auto\n%s\n' "$TEST_TMPDIR/bin/$group"8.3 > "$TEST_TMPDIR/alternatives/$group"
    done
    printf 'DEFAULT_PHP_VERSION=8.3\nLEMPER_PASSWORD=synthetic-profile-secret\n' > "$CONFIG_FILE"
    chmod 0600 "$CONFIG_FILE"
}
# shellcheck disable=SC2016 # Fixed child code; all mutation tools are fixture stubs.
php_child='
 . "$REAL_BASE_DIR/lib/core/loader.sh"
 . "$REAL_BASE_DIR/lib/runtime/stack/commands.sh"
 . "$REAL_BASE_DIR/lib/services/php/lifecycle.sh"
 . "$REAL_BASE_DIR/lib/services/php/defaults.sh"
 error() { printf "%s\n" "$*" >&2; }
 info() { printf "%s\n" "$*"; }
 success() { printf "%s\n" "$*"; }
 PATH="$TEST_TMPDIR/bin:$PATH"
 update-alternatives() {
    local action="$1" group="$2" mode value version
    [[ -f "$TEST_TMPDIR/alternatives/$group" ]] || return 1
    mapfile -t fixture < "$TEST_TMPDIR/alternatives/$group"
    mode="${fixture[0]}"; value="${fixture[1]}"
    case "$action" in
      --query)
        printf "Status: %s\nValue: %s\n" "$mode" "$value"
        for version in 8.3 8.4; do
          [[ "${UNREGISTERED_GROUP:-}" != "$group" || "$version" != 8.4 ]] || continue
          printf "Alternative: %s/bin/%s%s\n" "$TEST_TMPDIR" "$group" "$version"
        done ;;
      --set|--auto)
        printf "%s:%s\n" "$action" "$group" >> "$TEST_TMPDIR/mutations"
        if [[ -f "$TEST_TMPDIR/fail-$group" ]]; then rm "$TEST_TMPDIR/fail-$group"; return 1; fi
        if [[ "$action" == --set ]]; then mode=manual; value="$3"; else mode=auto; value="$TEST_TMPDIR/bin/${group}8.3"; fi
        printf "%s\n%s\n" "$mode" "$value" > "$TEST_TMPDIR/alternatives/$group" ;;
    esac
 }
'
@test "stack config php selects installed alternatives, persists default, and skips absent dev tools" {
    run bash -c "${php_child}"'init_lemper_stack config php --default-runtime=php@8.4'
    [ "$status" -eq 0 ]
    grep -qx DEFAULT_PHP_VERSION=8.4 "$CONFIG_FILE"
    grep -qx LEMPER_PASSWORD=synthetic-profile-secret "$CONFIG_FILE"
    [[ "$output" != *synthetic-profile-secret* ]]
    for group in php phar phar.phar; do grep -qx "$TEST_TMPDIR/bin/${group}8.4" "$TEST_TMPDIR/alternatives/$group"; done
    [ "$(stat -c %a "$CONFIG_FILE")" = 600 ]
    ! grep -q 'phpize\|php-config' "$TEST_TMPDIR/mutations"
}
@test "PHP default validates every registered target before changing any group" {
    run bash -c "${php_child}"'UNREGISTERED_GROUP=phar; init_lemper_stack config php --default-runtime=php@8.4'
    [ "$status" -ne 0 ]
    [ ! -f "$TEST_TMPDIR/mutations" ]
    grep -qx DEFAULT_PHP_VERSION=8.3 "$CONFIG_FILE"
}
@test "unsupported, malformed, conflicting and non-PHP defaults fail before mutation" {
    run bash -c "${php_child}"'
      init_lemper_stack config php --default-runtime=php@8.0 && exit 1
      init_lemper_stack config php --default-runtime="php@8.4;touch /tmp/bad" && exit 1
      init_lemper_stack config nginx --default-runtime=php@8.4 && exit 1
      init_lemper_stack config php --default-runtime=php@8.4 --default-runtime=php@8.3 && exit 1
      init_lemper_stack config php --default-runtime=php@8.4 --all-versions && exit 1
      exit 0
    '
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_TMPDIR/mutations" ]
}
@test "missing PHP CLI fails even when another alternative group is installed" {
    rm "$TEST_TMPDIR/bin/php8.4"
    run bash -c "${php_child}"'init_lemper_stack config php --default-runtime=php@8.4'
    [ "$status" -ne 0 ]
    [ ! -f "$TEST_TMPDIR/mutations" ]
}
@test "failure restores prior selections and auto/manual modes without changing the profile" {
    touch "$TEST_TMPDIR/fail-phar"
    printf 'manual\n%s\n' "$TEST_TMPDIR/bin/phar8.3" > "$TEST_TMPDIR/alternatives/phar"
    run bash -c "${php_child}"'init_lemper_stack config php --default-runtime=php@8.4'
    [ "$status" -ne 0 ]
    [ "$(head -1 "$TEST_TMPDIR/alternatives/php")" = auto ]
    [ "$(head -1 "$TEST_TMPDIR/alternatives/phar")" = manual ]
    for group in php phar phar.phar; do grep -qx "$TEST_TMPDIR/bin/${group}8.3" "$TEST_TMPDIR/alternatives/$group"; done
    grep -qx DEFAULT_PHP_VERSION=8.3 "$CONFIG_FILE"
}
@test "a profile commit failure rolls back alternatives and retains original credentials" {
    run bash -c "${php_child}"'
      lemper_exec() { if [[ "$1" == mv && "${@: -1}" == "$CONFIG_FILE" ]]; then return 1; fi; "$@"; }
      init_lemper_stack config php --default-runtime=php@8.4
    '
    [ "$status" -ne 0 ]
    grep -qx DEFAULT_PHP_VERSION=8.3 "$CONFIG_FILE"
    grep -qx LEMPER_PASSWORD=synthetic-profile-secret "$CONFIG_FILE"
    grep -qx "$TEST_TMPDIR/bin/php8.3" "$TEST_TMPDIR/alternatives/php"
}
@test "encrypted profiles retain encryption and secrets; repeating the same choice is a no-op" {
    run bash -c "${php_child}"'
      LEMPER_CONFIG_PASSWORD=synthetic-config-key
      openssl enc -aes-256-cbc -a -salt -md sha256 -pbkdf2 -pass fd:3 3<<<"$LEMPER_CONFIG_PASSWORD" \
        -in "$CONFIG_FILE" -out "$TEST_TMPDIR/encrypted" || exit 1
      mv "$TEST_TMPDIR/encrypted" "$CONFIG_FILE"
      init_lemper_stack config php --default-runtime=php@8.4 || exit 1
      is_config_encrypted "$CONFIG_FILE" || exit 1
      openssl enc -aes-256-cbc -d -a -salt -md sha256 -pbkdf2 -pass fd:3 3<<<"$LEMPER_CONFIG_PASSWORD" \
        -in "$CONFIG_FILE" -out "$TEST_TMPDIR/decoded" || exit 1
      grep -qx DEFAULT_PHP_VERSION=8.4 "$TEST_TMPDIR/decoded" || exit 1
      grep -qx LEMPER_PASSWORD=synthetic-profile-secret "$TEST_TMPDIR/decoded" || exit 1
      before=$(sha256sum "$CONFIG_FILE" "$TEST_TMPDIR/mutations")
      init_lemper_stack config php --default-runtime=php@8.4 || exit 1
      [[ "$before" == "$(sha256sum "$CONFIG_FILE" "$TEST_TMPDIR/mutations")" ]]
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *synthetic-profile-secret* && "$output" != *synthetic-config-key* ]]
}
@test "default dry run validates targets but creates no lock, profile backup, or mutations" {
    run bash -c "${php_child}"'init_lemper_stack config php --default-runtime=php@8.4 --dry-run'
    [ "$status" -eq 0 ]
    [[ "$output" == *'Would run:'* && "$output" != *synthetic-profile-secret* ]]
    [ ! -e "$LEMPER_OPERATION_LOCK" ]
    [ ! -e "$TEST_TMPDIR/mutations" ]
    [ "$(find "$TEST_TMPDIR" -name 'profile.*' | wc -l)" -eq 0 ]
}
