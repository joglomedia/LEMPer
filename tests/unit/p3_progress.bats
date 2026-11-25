#!/usr/bin/env bats
load env_helper
setup() { unit_setup; }
progress_child='
    . "$REAL_BASE_DIR/lib/core/loader.sh"
    lemper_load_module core/progress
    lemper_progress_now() { echo 160; }
'
@test "progress estimates remaining time from completed work and rejects empty samples" {
    run bash -c "$progress_child"'
        [[ $(lemper_progress_eta 2 5 100) == "~1m 30s" ]] || exit 1
        ! lemper_progress_eta 0 5 100 || exit 1
        ! lemper_progress_eta 5 5 100 || exit 1
        lemper_progress_reset 5 || exit 1
        [[ $PROGRESS_CURRENT == 0 && $PROGRESS_STARTED == 160 ]]
    '
    [ "$status" -eq 0 ]
}
@test "transfer outputs identical binary bytes without terminal escape noise" {
    printf '\000\001synthetic\377\n' > "$TEST_TMPDIR/source"
    run bash -c "$progress_child"' lemper_transfer_read "$TEST_TMPDIR/source" > "$TEST_TMPDIR/dest"; cmp "$TEST_TMPDIR/source" "$TEST_TMPDIR/dest"'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
@test "transfer dry-run emits no data and failed reads propagate" {
    run bash -c "$progress_child"'
        DRYRUN=true lemper_transfer_read "$REAL_BASE_DIR/.env.dist" > "$TEST_TMPDIR/out" || exit 1
        [[ ! -s "$TEST_TMPDIR/out" ]] || exit 1
        ! lemper_transfer_read "$TEST_TMPDIR/missing"
    '
    [ "$status" -eq 0 ]
}
@test "spinner cleanup succeeds under errexit and leaves no running spinner" {
    command -v script >/dev/null || skip 'util-linux script is required'
    cat > "$TEST_TMPDIR/spinner.sh" <<'SCRIPT'
. "$REAL_BASE_DIR/scripts/utils.sh"
set -e
DRYRUN=false
run_spinner 'Synthetic task' sleep 0.2
[[ -z "$SPINNER_PID" ]]
SCRIPT
    run env spinner_fixture="$TEST_TMPDIR/spinner.sh" script -q -e -c 'bash "$spinner_fixture"' /dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"Synthetic task"* ]]
}
@test "step output remains plain in CI and spinner diagnostics redact arguments" {
    run bash -c '
        . "$REAL_BASE_DIR/scripts/utils.sh"
        PROGRESS_TOTAL=2; PROGRESS_CURRENT=0; PROGRESS_STARTED=0
        progress build
        DRYRUN=true run_spinner "Synthetic task" echo --password synthetic-progress-secret
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"[1/2] build"* ]]
    [[ "$output" != *"ETA"* && "$output" != *"synthetic-progress-secret"* ]]
}
