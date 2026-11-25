#!/usr/bin/env bats
load env_helper
setup() { unit_setup; }

@test "protocol and integration acceptance refuse unprivileged shells before service changes" {
    local script
    for script in protocol_prepare.sh protocol_acceptance.sh remote_integrations_acceptance.sh; do
        run bash -c '
            id() { echo 1000; }
            export -f id
            bash "$1"
        ' _ "$REAL_BASE_DIR/tests/uat/$script"
        [ "$status" -eq 2 ]
    done
}

@test "SMTP fixture records literal message data privately without exposing it in replies" {
    mkdir -m 0700 "$TEST_TMPDIR/messages"
    cat > "$TEST_TMPDIR/transcript" <<'SMTP'
EHLO fixture.test
MAIL FROM:<sender@fixture.test>
RCPT TO:<receiver@fixture.test>
DATA
Subject: fixture
synthetic-alert-secret $(touch "$TEST_TMPDIR/executed")
.
QUIT
SMTP
    run bash -c '. "$1"; uat_smtp_session "$2" < "$3"' _ \
        "$REAL_BASE_DIR/tests/uat/smtp_sink.bash" "$TEST_TMPDIR/messages" "$TEST_TMPDIR/transcript"
    [ "$status" -eq 0 ]
    [[ "$output" == *'250 Accepted'* ]]
    [[ "$output" != *synthetic-alert-secret* ]]
    [ ! -e "$TEST_TMPDIR/executed" ]
    local message
    message=$(find "$TEST_TMPDIR/messages" -type f)
    [ "$(stat -c %a "$message")" = 600 ]
    grep -Fq '$(touch "$TEST_TMPDIR/executed")' "$message"
}

@test "SMTP fixture rejects an incomplete DATA transaction" {
    mkdir -m 0700 "$TEST_TMPDIR/messages"
    run bash -c '. "$1"; printf "DATA\nunfinished\n" | uat_smtp_session "$2"' _ \
        "$REAL_BASE_DIR/tests/uat/smtp_sink.bash" "$TEST_TMPDIR/messages"
    [ "$status" -ne 0 ]
    [[ "$output" != *'250 Accepted'* ]]
}
