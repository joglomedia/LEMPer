#!/usr/bin/env bats
# shellcheck disable=SC2016 # Child shell code intentionally retains literal expansions.
# shellcheck disable=SC2030,SC2031 # Bats isolates each test; fixture variables intentionally differ.
load env_helper

setup() {
    unit_setup
    export LEMPER_MYSQL_CONFIG_DIR="$TEST_TMPDIR/mysql"
    export LEMPER_MYSQL_MAIN_CONFIG="$TEST_TMPDIR/my.cnf"
    export LEMPER_MARIADB_PROFILE="$TEST_TMPDIR/profile"
    export MOCK_SQL="$TEST_TMPDIR/sql" MOCK_EXISTS=0 MOCK_FAIL=false
    export MARIABACKUP_USER=lemperdb MARIABACKUP_PASS=synthetic-backup
    export MARIABACKUP_USERNAME='' MARIABACKUP_PASSWORD='' MYSQL_ROOT_PASSWORD=synthetic-root
    export MOCK_EXPECTED_PASS=synthetic-backup
    mkdir -p "$LEMPER_MYSQL_CONFIG_DIR" "$TEST_TMPDIR/bin"
    cp "$REAL_BASE_DIR/.env.dist" "$LEMPER_MARIADB_PROFILE"
    chmod 0600 "$LEMPER_MARIADB_PROFILE"
    cat > "$TEST_TMPDIR/bin/mariadb" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
    *'SELECT COUNT('* ) printf '%s\n' "$MOCK_EXISTS" ;;
    *'SELECT 1;'* ) [[ "$MYSQL_PWD" == "$MOCK_EXPECTED_PASS" ]] ;;
    *) cat > "$MOCK_SQL"; [[ "$MOCK_FAIL" != true ]] ;;
esac
MOCK
    chmod +x "$TEST_TMPDIR/bin/mariadb"
}
provision() {
    run env PATH="$TEST_TMPDIR/bin:$PATH" bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        error() { printf "%s\n" "$*" >&2; }
        success() { printf "%s\n" "$*"; }
        resolve_config_password() { printf "synthetic-profile-key\n"; }
        lemper_load_module services/mariadb/backup
        lemper_with_lock lemper_mariabackup_provision
    '
}
@test "new backup credentials round-trip through SQL, real option parser and literal dotenv with private modes" {
    printf 'MARIABACKUP_PASS="\047inner quotes\047"\n' > "$TEST_TMPDIR/literal.env"
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        validate_config_file "$TEST_TMPDIR/literal.env"
        while IFS=$'\''\t'\'' read -r key value; do
            [[ "$value" == "'\''inner quotes'\''" ]] || exit 1
        done < <(safe_parse_dotenv "$TEST_TMPDIR/literal.env")
    '
    [ "$status" -eq 0 ]
    export MARIABACKUP_PASS="'quote \" slash\\ dollar\$(touch forbidden) # end'"
    provision
    [ "$status" -eq 0 ]
    [[ "$output" != *"$MARIABACKUP_PASS"* ]]
    [ "$(stat -c %a "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf")" = 600 ]
    [ "$(stat -c %a "$LEMPER_MARIADB_PROFILE")" = 600 ]
    run my_print_defaults --defaults-file="$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf" mariabackup
    [ "$status" -eq 0 ]
    [[ "$output" == *"--password=$MARIABACKUP_PASS"* ]]
    run bash -c '. "$REAL_BASE_DIR/lib/core/loader.sh"; while IFS=$'\''\t'\'' read -r key value; do if [[ "$key" == MARIABACKUP_PASS ]]; then [[ "$value" == "$MARIABACKUP_PASS" ]] || exit 1; fi; done < <(safe_parse_dotenv "$LEMPER_MARIADB_PROFILE")'
    [ "$status" -eq 0 ]
    grep -q 'NO_BACKSLASH_ESCAPES' "$MOCK_SQL"
    grep -q 'CREATE USER' "$MOCK_SQL"
    grep -qx "MYSQL_ROOT_PASSWORD=synthetic-root" "$LEMPER_MARIADB_PROFILE"
    [ ! -e "$TEST_TMPDIR/forbidden" ]
}
@test "legacy backup keys migrate to canonical names and cleared aliases" {
    export MARIABACKUP_USERNAME=legacy-backup MARIABACKUP_PASSWORD=legacy-secret MARIABACKUP_PASS=
    provision
    [ "$status" -eq 0 ]
    grep -qx "MARIABACKUP_USER=legacy-backup" "$LEMPER_MARIADB_PROFILE"
    grep -qx "MARIABACKUP_PASS=legacy-secret" "$LEMPER_MARIADB_PROFILE"
    grep -qx "MARIABACKUP_PASSWORD=" "$LEMPER_MARIADB_PROFILE"
}
@test "conflicting aliases and unsafe names or control characters fail before database mutations" {
    export MARIABACKUP_USER=canonical MARIABACKUP_USERNAME=conflicting
    provision
    [ "$status" -ne 0 ]
    export MARIABACKUP_USERNAME=
    local invalid
    for invalid in root "name'quoted" 'name;id' $'multi\nline'; do
        export MARIABACKUP_USER="$invalid"
        provision
        [ "$status" -ne 0 ]
    done
    export MARIABACKUP_USER=lemperdb MARIABACKUP_PASS=$'secret\tvalue'
    provision
    [ "$status" -ne 0 ]
    [ ! -e "$MOCK_SQL" ]
    [ ! -e "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf" ]
}
@test "existing account configuration is repaired without CREATE or ALTER USER" {
    export MOCK_EXISTS=1
    provision
    [ "$status" -eq 0 ]
    [ -f "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf" ]
    run grep -qE 'CREATE USER|ALTER USER' "$MOCK_SQL"
    [ "$status" -eq 1 ]
    provision
    [ "$status" -eq 0 ]
    run grep -qE 'CREATE USER|ALTER USER' "$MOCK_SQL"
    [ "$status" -eq 1 ]
}
@test "existing accounts with missing or wrong credentials fail without replacing configuration" {
    export MOCK_EXISTS=1 MARIABACKUP_PASS=incorrect
    local before
    before=$(sha256sum "$LEMPER_MARIADB_PROFILE")
    provision
    [ "$status" -ne 0 ]
    [ "$(sha256sum "$LEMPER_MARIADB_PROFILE")" = "$before" ]
    printf '[mariabackup]\nuser=lemperdb\npassword=synthetic-backup\n' > "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf"
    chmod 0644 "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf"
    provision
    [ "$status" -ne 0 ]
    [ "$(stat -c %a "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf")" = 600 ]
    rm "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf"
    export MARIABACKUP_PASS=
    provision
    [ "$status" -ne 0 ]
    [ ! -e "$MOCK_SQL" ]
}
@test "legacy readable drop-in supplies existing credentials and retains tuning with protected backups" {
    export MOCK_EXISTS=1 MARIABACKUP_PASS=
    printf '[mariabackup]\nuser=lemperdb\npassword=synthetic-backup\nparallel=2\n' > "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf"
    chmod 0644 "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf"
    provision
    [ "$status" -eq 0 ]
    [ "$(stat -c %a "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf")" = 600 ]
    grep -qx 'parallel=2' "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf"
    local backup
    for backup in "$LEMPER_MYSQL_CONFIG_DIR"/*.pre-backup.* "$LEMPER_MARIADB_PROFILE".pre-backup.*; do
        [ "$(stat -c %a "$backup")" = 600 ]
    done
}
@test "SQL failure propagates and retains private credentials for retry without secret diagnostics" {
    export MOCK_FAIL=true MARIABACKUP_PASS=
    provision
    [ "$status" -ne 0 ]
    [[ "$output" == *'retained for retry'* ]]
    [ "$(stat -c %a "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf")" = 600 ]
    [ "$(stat -c %a "$LEMPER_MARIADB_PROFILE")" = 600 ]
    [ -z "$(find "$LEMPER_MYSQL_CONFIG_DIR" -name '.mariabackup.*')" ]
}
@test "dry-run creates no credentials, lock or database statements" {
    export DRYRUN=true
    provision
    [ "$status" -eq 0 ]
    [[ "$output" != *synthetic-backup* ]]
    [ ! -e "$MOCK_SQL" ]
    [ ! -e "$LEMPER_OPERATION_LOCK" ]
    [ ! -e "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf" ]
}
@test "symlink and untrusted destinations or unrelated configuration groups are preserved" {
    printf unchanged > "$TEST_TMPDIR/foreign"
    ln -s "$TEST_TMPDIR/foreign" "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf"
    provision
    [ "$status" -ne 0 ]
    [ "$(cat "$TEST_TMPDIR/foreign")" = unchanged ]
    rm "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf"
    printf '[mysqld]\nport=3306\n' > "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf"
    provision
    [ "$status" -ne 0 ]
    grep -qx '\[mysqld\]' "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf"
    rm "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf"
    chmod 0666 "$LEMPER_MARIADB_PROFILE"
    provision
    [ "$status" -ne 0 ]
    chmod 0600 "$LEMPER_MARIADB_PROFILE"
    chmod 0777 "$LEMPER_MYSQL_CONFIG_DIR"
    provision
    [ "$status" -ne 0 ]
    [ ! -e "$MOCK_SQL" ]
}
@test "encrypted profiles remain encrypted and unrelated settings survive reconciliation" {
    openssl enc -aes-256-cbc -a -salt -md sha256 -pbkdf2 -pass fd:3 3<<<synthetic-profile-key \
        -in "$LEMPER_MARIADB_PROFILE" -out "$TEST_TMPDIR/encrypted"
    mv "$TEST_TMPDIR/encrypted" "$LEMPER_MARIADB_PROFILE"
    provision
    [ "$status" -eq 0 ]
    run grep -q MARIABACKUP "$LEMPER_MARIADB_PROFILE"
    [ "$status" -eq 1 ]
    openssl enc -d -aes-256-cbc -a -md sha256 -pbkdf2 -pass fd:3 3<<<synthetic-profile-key \
        -in "$LEMPER_MARIADB_PROFILE" -out "$TEST_TMPDIR/plain"
    grep -qx "MARIABACKUP_PASS=synthetic-backup" "$TEST_TMPDIR/plain"
    grep -qx 'MYSQL_VERSION="11.4"' "$TEST_TMPDIR/plain"
}

@test "inline my.cnf backup credentials migrate without replacing distribution symlinks or unrelated settings" {
    export MOCK_EXISTS=1 MARIABACKUP_PASS=''
    printf '[mysqld]\nport=3306\n[mariabackup]\nuser=lemperdb\npassword=synthetic-backup\nopen_files_limit=65535\n[client]\nsocket=/run/mysql.sock\n' > "$TEST_TMPDIR/main.cnf"
    chmod 0644 "$TEST_TMPDIR/main.cnf"
    ln -s "$TEST_TMPDIR/main.cnf" "$LEMPER_MYSQL_MAIN_CONFIG"
    provision
    [ "$status" -eq 0 ]
    [ -L "$LEMPER_MYSQL_MAIN_CONFIG" ]
    run grep -qE '^[[:space:]]*(\[mariabackup\]|password[[:space:]]*=)' "$TEST_TMPDIR/main.cnf"
    [ "$status" -eq 1 ]
    grep -qx 'port=3306' "$TEST_TMPDIR/main.cnf"
    grep -qx 'socket=/run/mysql.sock' "$TEST_TMPDIR/main.cnf"
    [ "$(stat -c %a "$TEST_TMPDIR/main.cnf")" = 644 ]
    local backup
    for backup in "$TEST_TMPDIR/main.cnf".pre-inline.*; do
        [ "$(stat -c %a "$backup")" = 600 ]
    done
    [ "$(stat -c %a "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf")" = 600 ]
}

@test "protected root credentials survive a later backup preflight failure" {
    export MARIABACKUP_USER=canonical MARIABACKUP_USERNAME=conflicting
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        lemper_load_module services/mariadb/backup
        lemper_with_lock lemper_mariadb_store_root_credential || exit 1
        lemper_with_lock lemper_mariabackup_provision
    '
    [ "$status" -ne 0 ]
    grep -qx "MYSQL_ROOT_PASSWORD=synthetic-root" "$LEMPER_MARIADB_PROFILE"
    [ "$(stat -c %a "$LEMPER_MARIADB_PROFILE")" = 600 ]
    [ ! -e "$MOCK_SQL" ]
    local backup
    for backup in "$LEMPER_MARIADB_PROFILE".pre-root.*; do
        [ "$(stat -c %a "$backup")" = 600 ]
    done
    chmod 0644 "$LEMPER_MARIADB_PROFILE"
    run bash -c '. "$REAL_BASE_DIR/lib/core/loader.sh"; lemper_load_module services/mariadb/backup; lemper_with_lock lemper_mariadb_store_root_credential'
    [ "$status" -eq 0 ]
    [ "$(stat -c %a "$LEMPER_MARIADB_PROFILE")" = 600 ]
}

@test "merged and reloaded profiles preserve actual outer password quotes" {
    export MYSQL_ROOT_PASSWORD="'root quote'" MARIABACKUP_PASS='"backup quote"'
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        . "$REAL_BASE_DIR/lib/runtime/stack/entry.sh"
        lemper_load_module services/mariadb/backup
        lemper_with_lock lemper_mariadb_store_root_credential || exit 1
        set_env_value "$LEMPER_MARIADB_PROFILE" MARIABACKUP_PASS "$MARIABACKUP_PASS" || exit 1
        cp "$REAL_BASE_DIR/.env.dist" "$TEST_TMPDIR/merged"
        lemper_entry_merge_profile "$LEMPER_MARIADB_PROFILE" "$TEST_TMPDIR/merged" || exit 1
        validate_config_file "$TEST_TMPDIR/merged" || exit 1
        while IFS=$'\''\t'\'' read -r key value; do
            case "$key" in
                MYSQL_ROOT_PASSWORD) [[ "$value" == "$MYSQL_ROOT_PASSWORD" ]] || exit 1 ;;
                MARIABACKUP_PASS) [[ "$value" == "$MARIABACKUP_PASS" ]] || exit 1 ;;
            esac
        done < <(safe_parse_dotenv "$TEST_TMPDIR/merged")
    '
    [ "$status" -eq 0 ]
    printf 'MYSQL_ROOT_PASSWORD="invalid\t"\n' > "$TEST_TMPDIR/invalid-root"
    run bash -c '. "$REAL_BASE_DIR/lib/core/loader.sh"; validate_config_file "$TEST_TMPDIR/invalid-root"'
    [ "$status" -ne 0 ]
    printf 'MYSQL_ROOT_PASSWORD=invalid\000value\n' > "$TEST_TMPDIR/invalid-root"
    run bash -c '. "$REAL_BASE_DIR/lib/core/loader.sh"; validate_config_file "$TEST_TMPDIR/invalid-root"'
    [ "$status" -ne 0 ]
}

@test "legacy installer rejects a held operation lock before its service callback and propagates failure" {
    local fixture="$TEST_TMPDIR/legacy"
    mkdir -p "$fixture/lib/core" "$fixture/scripts"
    cp "$REAL_BASE_DIR/.env.dist" "$fixture/.env.dist"
    ssh-keygen -q -t ed25519 -N '' -f "$fixture/key"
    run bash -c '. "$REAL_BASE_DIR/lib/core/loader.sh"; set_env_value "$1" RSA_PUB_KEY "$2"' \
        _ "$fixture/.env.dist" "$(cat "$fixture/key.pub")"
    [ "$status" -eq 0 ]
    cat > "$fixture/lib/core/lemper-stacks.sh" <<'FIXTURE'
. "$REAL_BASE_DIR/lib/core/loader.sh"
. "$BASE_DIR/scripts/utils.sh"
lemper_install() { printf 'SERVICE_MUTATION\n'; }
lemper_remove() { printf 'SERVICE_MUTATION\n'; }
FIXTURE
    cat > "$fixture/scripts/utils.sh" <<'FIXTURE'
. "$REAL_BASE_DIR/lib/core/loader.sh"
export ENVFILE="$BASE_DIR/.env"
run() { "$@"; }
sed_inplace() { sed -i "$@"; }
error() { printf '%s\n' "$*" >&2; }
preflight_system_check() { :; }
header_msg() { :; }
footer_msg() { :; }
FIXTURE
    run env LEMPER_INSTALL_ROOT="$fixture" bash -c '
        exec {fd}> "$LEMPER_OPERATION_LOCK"
        flock -n "$fd" || exit 1
        bash "$REAL_BASE_DIR/lib/compat/installer.sh" install
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *'Another LEMPer operation is running.'* ]]
    [[ "$output" != *SERVICE_MUTATION* ]]
    run env LEMPER_INSTALL_ROOT="$fixture" bash "$REAL_BASE_DIR/lib/compat/installer.sh" install
    [ "$status" -eq 0 ]
    [[ "$output" == *SERVICE_MUTATION* ]]
}

@test "inline credentials become private even when the database is unavailable" {
    printf '[mysqld]\nport=3306\n[mariabackup] # backup account\nuser=lemperdb\npassword=synthetic-backup\n' > "$LEMPER_MYSQL_MAIN_CONFIG"
    chmod 0644 "$LEMPER_MYSQL_MAIN_CONFIG"
    printf '#!/usr/bin/env bash\nexit 1\n' > "$TEST_TMPDIR/bin/mariadb"
    provision
    [ "$status" -ne 0 ]
    [ "$(stat -c %a "$LEMPER_MYSQL_CONFIG_DIR/.lemper-inline-mariabackup.cnf")" = 600 ]
    run grep -qE '^[[:space:]]*(\[mariabackup\]|password[[:space:]]*=)' "$LEMPER_MYSQL_MAIN_CONFIG"
    [ "$status" -eq 1 ]
    grep -qx 'port=3306' "$LEMPER_MYSQL_MAIN_CONFIG"
    run my_print_defaults --defaults-file="$LEMPER_MYSQL_MAIN_CONFIG" mariabackup
    [ "$status" -eq 0 ]
    [[ "$output" == *'--password=synthetic-backup'* ]]
}

@test "installer root bootstrap rejects RNG errors and empty output before SQL and retains a successful password" {
    # Load the inspected definitions with the source-time installer dispatch removed.
    sed '/^echo "\[MariaDB /,$d' "$REAL_BASE_DIR/scripts/install_mariadb.sh" > "$TEST_TMPDIR/installer-functions.sh"
    local mode
    for mode in fail empty writefail success; do
        rm -f "$MOCK_SQL"
        run env MOCK_RNG="$mode" bash -c '
            . "$REAL_BASE_DIR/lib/core/loader.sh"
            run() { :; }
            . "$TEST_TMPDIR/installer-functions.sh"
            error() { printf "%s\n" "$*" >&2; }
            run_spinner() { :; }
            add_mariadb_repo() { :; }
            tune_mariadb_config() { :; }
            allow_remote_client_access() { :; }
            enable_mariabackup() { :; }
            pgrep() { printf "1\n"; }
            openssl() {
                case "$MOCK_RNG" in fail) return 7 ;; empty) return 0 ;; writefail|success) printf "generated-root\n" ;; esac
            }
            cat() {
                if [[ "$MOCK_RNG" == writefail && $# == 1 && "$1" == "$LEMPER_MARIADB_PROFILE".plain.* ]]; then return 8; fi
                command cat "$@"
            }
            mariadb() { cat > "$MOCK_SQL"; }
            INSTALL_MYSQL=true AUTO_INSTALL=true MYSQL_SECURE_INSTALL=true DRYRUN=false MYSQL_ROOT_PASSWORD=""
            lemper_with_lock init_mariadb_install
        '
        if [[ "$mode" == success ]]; then
            [ "$status" -eq 0 ]
            [ -f "$MOCK_SQL" ]
            grep -qx 'MYSQL_ROOT_PASSWORD=generated-root' "$LEMPER_MARIADB_PROFILE"
            [ "$(stat -c %a "$LEMPER_MARIADB_PROFILE")" = 600 ]
        else
            [ "$status" -ne 0 ]
            [ ! -e "$MOCK_SQL" ]
        fi
    done
}

@test "inline migration preserves later tuning precedence while synchronizing both protected credential copies" {
    export MOCK_EXISTS=1
    printf '[mariabackup]\nparallel=1\nuser=lemperdb\npassword=synthetic-backup\n' > "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf"
    printf '[mariabackup]\nparallel=2\n' > "$TEST_TMPDIR/tuning.cnf"
    printf '!includedir %s\n!include %s\n[mariabackup] # credentials\nuser=lemperdb\npassword=synthetic-backup\n' \
        "$LEMPER_MYSQL_CONFIG_DIR" "$TEST_TMPDIR/tuning.cnf" > "$LEMPER_MYSQL_MAIN_CONFIG"
    provision
    [ "$status" -eq 0 ]
    run my_print_defaults --defaults-file="$LEMPER_MYSQL_MAIN_CONFIG" mariabackup
    [ "$status" -eq 0 ]
    local option parallel=''
    for option in "${lines[@]}"; do
        [[ "$option" != --parallel=* ]] || parallel="$option"
    done
    [ "$parallel" = --parallel=2 ]
    [[ "$output" == *'--password=synthetic-backup'* ]]
    [ "$(stat -c %a "$LEMPER_MYSQL_CONFIG_DIR/.lemper-inline-mariabackup.cnf")" = 600 ]
}

@test "verified credentials remain authoritative after retained tuning includes" {
    export MOCK_EXISTS=1
    printf '[mariabackup]\npassword=synthetic-old\n' > "$TEST_TMPDIR/old.cnf"
    printf '[mariabackup]\nuser=lemperdb\npassword=synthetic-old\n!include %s\n' "$TEST_TMPDIR/old.cnf" \
        > "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf"
    provision
    [ "$status" -eq 0 ]
    run my_print_defaults --defaults-file="$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf" mariabackup
    [ "$status" -eq 0 ]
    local option password=''
    for option in "${lines[@]}"; do
        [[ "$option" != --password=* ]] || password="$option"
    done
    [ "$password" = --password=synthetic-backup ]
    grep -q '^!include ' "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf"
}

@test "legacy escaped control values cannot truncate or forge recovered credentials" {
    export MARIABACKUP_PASS=''
    local value
    for value in 'before\nafter' 'before\n--password=forged' 'before\tafter'; do
        printf '[mariabackup]\nuser=lemperdb\npassword="%s"\n' "$value" > "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf"
        provision
        [ "$status" -ne 0 ]
        [ ! -e "$MOCK_SQL" ]
    done
    printf '[mariabackup]\nuser=lemperdb\npassword="before\\\\nafter"\n' > "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf"
    provision
    [ "$status" -eq 0 ]
    grep -q 'CREATE USER' "$MOCK_SQL"
    run my_print_defaults --defaults-file="$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf" mariabackup
    [ "$status" -eq 0 ]
    [[ "$output" == *'--password=before\nafter'* ]]
    # Native MySQL treats quotes in !include names as filename characters.
    # The safe absolute file and the actual quoted relative file are different.
    rm -f "$MOCK_SQL"
    cd "$TEST_TMPDIR" || return 1
    local safe="$TEST_TMPDIR/safe.cnf" actual="\"$TEST_TMPDIR/safe.cnf\""
    printf '[mariabackup]\npassword=synthetic-safe\n' > "$safe"
    mkdir -p "${actual%/*}"
    printf '[mariabackup]\npassword=synthetic-untrusted\n' > "$actual"
    chown nobody "$actual"
    printf '[mariabackup]\nuser=lemperdb\n!include "%s"\n' "$safe" > "$LEMPER_MYSQL_CONFIG_DIR/50-mariabackup.cnf"
    provision
    [ "$status" -ne 0 ]
    [ ! -e "$MOCK_SQL" ]
}
