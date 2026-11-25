#!/usr/bin/env bats
load env_helper
setup() {
    unit_setup
    export LEMPER_TEST_HASH='{SHA512-CRYPT}$6$test'
    export LEMPER_MAIL_ROOT="$TEST_TMPDIR/mail"
    export LEMPER_MAIL_HOME_ROOT="$TEST_TMPDIR/vmail"
    export LEMPER_OPERATION_LOCK="$TEST_TMPDIR/operation.lock"
    mkdir -p "$LEMPER_MAIL_ROOT/generations/initial" "$LEMPER_MAIL_HOME_ROOT"
    touch "$LEMPER_MAIL_ROOT/managed"
    printf 'first.test\tOK\nsecond.test\tOK\n' > "$LEMPER_MAIL_ROOT/generations/initial/domains"
    printf 'alice@first.test\t{SHA512-CRYPT}$6$synthetic\tenabled\nbob@second.test\t{SHA512-CRYPT}$6$synthetic\tenabled\n' > "$LEMPER_MAIL_ROOT/generations/initial/accounts"
    : > "$LEMPER_MAIL_ROOT/generations/initial/aliases"
    chmod 0600 "$LEMPER_MAIL_ROOT/generations/initial/accounts"
    ln -s "$LEMPER_MAIL_ROOT/generations/initial" "$LEMPER_MAIL_ROOT/current"
}
# shellcheck disable=SC2016 # Fixed code executed by the isolated child.
mail_child='
 . "$REAL_BASE_DIR/lib/core/loader.sh"
 . "$REAL_BASE_DIR/lib/services/mail/store.sh"
 . "$REAL_BASE_DIR/lib/runtime/mail/commands.sh"
 error() { printf "%s\n" "$*" >&2; }
 info() { printf "%s\n" "$*"; }
 success() { printf "%s\n" "$*"; }
 chown() { :; }
 postmap() { local p="${1#hash:}"; cp "$p" "$p.db"; }
 lemper_mail_check() { :; }
 lemper_mail_reload() { :; }
 doveadm() { :; }
 lemper_load_module() { :; }
'
@test "mail help is public without configuration, root, or source-time effects" {
    run test_run_public "$REAL_BASE_DIR" bin/lemper-cli.sh mail account add --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--password-file"* ]]
    run bash -c 'for f in "$1"/lib/services/mail/*.sh "$1"/lib/runtime/mail/*.sh; do . "$f" || exit 1; done; echo SOURCED' _ "$REAL_BASE_DIR"
    [ "$status" -eq 0 ]
    [ "$output" = SOURCED ]
}
@test "mail rejects unsafe addresses and unsupported options before creating a generation" {
    run bash -c "${mail_child}"'
        for address in "../x@first.test" "a@first.test/../../tmp" "a\$(touch nope)@first.test" "Alice@first.test" "a..b@first.test" "a@first.test."; do
            init_lemper_mail account add "$address" --dry-run && exit 1
        done
        init_lemper_mail account add alice@first.test --password plaintext && exit 1
        init_lemper_mail alias add team@first.test bob@second.test extra && exit 1
        init_lemper_mail account edit alice@first.test --enable --disable && exit 1
        exit 0
    '
    [ "$status" -eq 0 ]
    [ "$(readlink "$LEMPER_MAIL_ROOT/current")" = "$LEMPER_MAIL_ROOT/generations/initial" ]
}
@test "multiple domains and cross-domain aliases build consistent maps without exposing hashes" {
    run bash -c "${mail_child}"'
        init_lemper_mail domain add third.test || exit 1
        init_lemper_mail alias add team@third.test bob@second.test || exit 1
        init_lemper_mail account list
        init_lemper_mail alias list third.test
        grep -qx "team@third.test$(printf "\t")bob@second.test" "$LEMPER_MAIL_ROOT/current/sender_login"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"alice@first.test"*"enabled"*"team@third.test"*"bob@second.test"* ]]
    [[ "$output" != *'$6$'* ]]
    [ "$(stat -c %a "$LEMPER_MAIL_ROOT/current/passwd")" = 640 ]
    [ "$(stat -c %a "$LEMPER_MAIL_ROOT/current/accounts")" = 600 ]
}
@test "account disable and enable preserve password and delivery but remove login permissions" {
    run bash -c "${mail_child}"'
        init_lemper_mail account edit alice@first.test --disable || exit 1
        grep -q "alice@first.test" "$LEMPER_MAIL_ROOT/current/mailboxes" || exit 1
        grep -q "alice@first.test" "$LEMPER_MAIL_ROOT/current/passwd" && exit 1
        init_lemper_mail account edit alice@first.test --enable || exit 1
        grep -q "alice@first.test" "$LEMPER_MAIL_ROOT/current/passwd"
    '
    [ "$status" -eq 0 ]
    grep -q 'alice@first.test.*{SHA512-CRYPT}\$6\$synthetic.*enabled' "$LEMPER_MAIL_ROOT/current/accounts"
}
@test "account deletion refuses dependent aliases and domain deletion refuses accounts" {
    run bash -c "${mail_child}"'
        init_lemper_mail alias add team@first.test bob@second.test || exit 1
        init_lemper_mail account delete bob@second.test --yes && exit 1
        init_lemper_mail domain delete first.test --yes && exit 1
        init_lemper_mail alias edit team@first.test alice@first.test || exit 1
        init_lemper_mail account delete bob@second.test --yes || exit 1
        init_lemper_mail domain delete second.test --yes
    '
    [ "$status" -eq 0 ]
    ! grep -q '^second.test' "$LEMPER_MAIL_ROOT/current/domains"
}
@test "failed validation and failed reload restore the previous generation and report failure" {
    run bash -c "${mail_child}"'
        original=$(readlink "$LEMPER_MAIL_ROOT/current")
        lemper_mail_check() { return 1; }
        init_lemper_mail domain add third.test && exit 1
        [[ "$(readlink "$LEMPER_MAIL_ROOT/current")" == "$original" ]] || exit 1
        lemper_mail_check() { :; }
        lemper_mail_reload() { return 1; }
        init_lemper_mail alias add team@first.test bob@second.test && exit 1
        [[ "$(readlink "$LEMPER_MAIL_ROOT/current")" == "$original" ]]
    '
    [ "$status" -eq 0 ]
}
@test "dry run skips password reads, locking, key generation, and all filesystem changes" {
    run bash -c "${mail_child}"'
        init_lemper_mail account add charlie@first.test --password-file /no/such/file --dry-run || exit 1
        init_lemper_mail alias add team@first.test bob@second.test --dry-run || exit 1
        init_lemper_mail domain add third.test --dry-run || exit 1
        . "$REAL_BASE_DIR/lib/services/mail/store.sh"
        DRYRUN=true
        postfix() { echo MUTATED; }
        doveconf() { echo MUTATED; }
        lemper_mail_check
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *MUTATED* ]]
    [ "$(find "$LEMPER_MAIL_ROOT/generations" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ]
    [ ! -e "$LEMPER_OPERATION_LOCK" ]
}
@test "deletion retains mail by default and purge rejects symlinks and missing confirmation" {
    mkdir -p "$LEMPER_MAIL_HOME_ROOT/second.test/bob/Maildir" "$TEST_TMPDIR/keep"
    printf 'retained\n' > "$TEST_TMPDIR/keep/message"
    ln -s "$TEST_TMPDIR/keep" "$LEMPER_MAIL_HOME_ROOT/first.test"
    run bash -c "${mail_child}"'
        init_lemper_mail account delete bob@second.test --purge && exit 1
        init_lemper_mail account delete alice@first.test --purge --yes && exit 1
        init_lemper_mail account delete bob@second.test --yes
    '
    [ "$status" -eq 0 ]
    [ -d "$LEMPER_MAIL_HOME_ROOT/second.test/bob/Maildir" ]
    [ -f "$TEST_TMPDIR/keep/message" ]
}
@test "password input requires a protected single-line file and never logs the password" {
    printf 'synthetic-password-only\n' > "$TEST_TMPDIR/password"
    chmod 0600 "$TEST_TMPDIR/password"
    run bash -c "${mail_child}"'
        doveadm() { cat >/dev/null; printf "%s\n" "$LEMPER_TEST_HASH"; }
        init_lemper_mail account add charlie@first.test --password-file "$TEST_TMPDIR/password"
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *synthetic-password-only* ]]
    chmod 0644 "$TEST_TMPDIR/password"
    run bash -c "${mail_child}"'init_lemper_mail account add unsafe@first.test --password-file "$TEST_TMPDIR/password"'
    [ "$status" -ne 0 ]
    [[ "$output" != *synthetic-password-only* ]]
}
@test "production mail installation rejects missing certificates before package or service changes" {
    run bash -c "${mail_child}"'
        . "$REAL_BASE_DIR/lib/services/mail/configure.sh"
        MAILER_HOSTNAME=mail.first.test
        SENDER_DOMAIN=first.test
        MAILER_CERT_PATH="$TEST_TMPDIR/missing-certificate"
        ENVIRONMENT=production
        lemper_exec() { echo MUTATED; }
        lemper_mail_install
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *"certificate"* && "$output" != *MUTATED* ]]
}
@test "an interrupted owned mail install can be retried while an unmanaged installation is protected" {
    rm "$LEMPER_MAIL_ROOT/managed"
    run bash -c "${mail_child}"'
        . "$REAL_BASE_DIR/lib/services/mail/configure.sh"
        MAILER_HOSTNAME=mail.first.test SENDER_DOMAIN=first.test ENVIRONMENT=development DRYRUN=true
        postfix() { :; }
        lemper_mail_install && exit 1
        touch "$LEMPER_MAIL_ROOT/installing"
        lemper_mail_install
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"unmanaged"* && "$output" == *"Would install"* ]]
    [ "$(find "$LEMPER_MAIL_ROOT/generations" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ]
}
@test "editing an account accepts no-session kick status but reports a real session-control failure" {
    run bash -c "${mail_child}"'
        doveadm() { [[ "$1" != kick ]] || return 68; }
        init_lemper_mail account edit alice@first.test --disable || exit 1
        doveadm() { [[ "$1" != kick ]] || return 1; }
        init_lemper_mail account edit alice@first.test --enable && exit 1
        exit 0
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unable to disconnect"* ]]
}

@test "mail reconciliation preserves stronger outbound TLS while configuring the server" {
    run bash -c "${mail_child}"'
        . "$REAL_BASE_DIR/lib/services/mail/configure.sh"
        postconf() {
            if [[ "$1" == -h ]]; then printf "%s\n" "$policy"; return; fi
            if [[ "$1" == -e ]]; then
                case "$2" in
                    smtp_tls_security_level=*) policy="${2#*=}" ;;
                    myhostname=*) configured_hostname="${2#*=}" ;;
                esac
            fi
        }
        for requested in encrypt verify secure dane dane-only fingerprint; do
            policy="$requested" configured_hostname=""
            lemper_mail_postfix_configure mail.first.test /certificate "$LEMPER_MAIL_ROOT" || exit 1
            [[ "$policy" == "$requested" && "$configured_hostname" == mail.first.test ]] || exit 1
        done
    '
    [ "$status" -eq 0 ]
}

@test "mail reconciliation enables opportunistic outbound TLS for fresh defaults" {
    run bash -c "${mail_child}"'
        . "$REAL_BASE_DIR/lib/services/mail/configure.sh"
        postconf() {
            if [[ "$1" == -h ]]; then printf "%s\n" "$policy"; return; fi
            [[ "$1" != -e || "$2" != smtp_tls_security_level=* ]] || policy="${2#*=}"
            return 0
        }
        for requested in none may ""; do
            policy="$requested"
            lemper_mail_postfix_configure mail.first.test /certificate "$LEMPER_MAIL_ROOT" || exit 1
            [[ "$policy" == may ]] || exit 1
        done
    '
    [ "$status" -eq 0 ]
}

@test "mail reconciliation aborts before mutation if the existing TLS policy cannot be read" {
    run bash -c "${mail_child}"'
        . "$REAL_BASE_DIR/lib/services/mail/configure.sh"
        postconf() { [[ "$1" != -h ]] || return 47; echo MUTATED; }
        lemper_mail_postfix_configure mail.first.test /certificate "$LEMPER_MAIL_ROOT"
    '
    [ "$status" -ne 0 ]
    [[ "$output" != *MUTATED* ]]
}

@test "mail reconciliation refuses an unrecognized outbound TLS policy without mutation" {
    run bash -c "${mail_child}"'
        . "$REAL_BASE_DIR/lib/services/mail/configure.sh"
        postconf() { if [[ "$1" == -h ]]; then echo unexpected; else echo MUTATED; fi; }
        lemper_mail_postfix_configure mail.first.test /certificate "$LEMPER_MAIL_ROOT"
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unsupported outbound SMTP TLS policy"* ]]
    [[ "$output" != *MUTATED* ]]
}
