#!/usr/bin/env bats
# shellcheck disable=SC2016 # Literal child shells/test values.
load env_helper
setup() { unit_setup; }

@test "repository-owned library, test and tooling helpers have no foreign-language script files" {
    run find "$REAL_BASE_DIR/lib" "$REAL_BASE_DIR/tests" "$REAL_BASE_DIR/scripts" -type f \
        \( -name '*.py' -o -name '*.rb' -o -name '*.pl' -o -name '*.js' -o -name '*.ts' \)
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    local script first
    while IFS= read -r -d '' script; do
        IFS= read -r first <"$script" || true
        [[ "$first" != '#!'* ]] || [[ "$first" == *bash* || "$first" == *bats* ]]
    done < <(find "$REAL_BASE_DIR/sbin" "$REAL_BASE_DIR/share/memcached/scripts" "$REAL_BASE_DIR/etc/init.d" -type f -print0)
}
@test "new Bash service modules load without dispatch, traps or shell-option changes" {
    run bash -c '
        . "$REAL_BASE_DIR/lib/core/loader.sh"
        before_options="$-" before_traps="$(trap -p)" before_umask="$(umask)"
        for module in services/site/inspect services/site/release_metadata services/site/release_archive services/site/release_prepare services/mariadb/option_guard; do
            lemper_load_module "$module" || exit
        done
        [[ "$-" == "$before_options" && "$(trap -p)" == "$before_traps" && "$(umask)" == "$before_umask" ]]
    '
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
@test "Bash coverage canonicalizes observed paths and reports unentered functions without tracing arguments" {
    mkdir -p "$TEST_TMPDIR/source/tests" "$TEST_TMPDIR/source/lib"
    printf 'lib/demo.sh\n' >"$TEST_TMPDIR/source/tests/coverage_scope.txt"
    printf 'function entered() { :; }\nfunction unseen() { :; }\n' >"$TEST_TMPDIR/source/lib/demo.sh"
    printf '%s\tentered\n%s\tentered\n' "$TEST_TMPDIR/source/lib/../lib/demo.sh" "$TEST_TMPDIR/source/lib/demo.sh" >"$TEST_TMPDIR/trace"
    run bash "$REAL_BASE_DIR/tests/report_coverage.sh" "$TEST_TMPDIR/source" "$TEST_TMPDIR/trace" "$TEST_TMPDIR/report"
    [ "$status" -eq 0 ]
    [[ "$output" == *'1/2 (50.0%)'* ]]
    run jq -e '.metric=="function entry" and .entered==1 and .total==2 and .functions[0].entered and (.functions[1].entered|not)' "$TEST_TMPDIR/report/functions.json"
    [ "$status" -eq 0 ]
    grep -Fq '| lib/demo.sh | unseen | no |' "$TEST_TMPDIR/report/functions.md"
    printf 'lib/missing.sh\n' >"$TEST_TMPDIR/source/tests/coverage_scope.txt"
    run bash "$REAL_BASE_DIR/tests/report_coverage.sh" "$TEST_TMPDIR/source" "$TEST_TMPDIR/trace" "$TEST_TMPDIR/missing-report"
    [ "$status" -ne 0 ] && [ ! -d "$TEST_TMPDIR/missing-report" ]
}
@test "Bash MariaDB option guard rejects binary input and include cycles before native parsing" {
    local file="$TEST_TMPDIR/options.cnf"
    printf '[mariabackup]\npassword=before\0after\n' >"$file"
    run bash -c '. "$REAL_BASE_DIR/lib/core/loader.sh"; lemper_load_module services/mariadb/option_guard; lemper_mariadb_option_guard "$1"' _ "$file"
    [ "$status" -ne 0 ]
    [[ "$output" != *before* && "$output" != *after* ]]
    printf '!include %s\n[mariabackup]\n' "$file" >"$file"
    run bash -c '. "$REAL_BASE_DIR/lib/core/loader.sh"; lemper_load_module services/mariadb/option_guard; lemper_mariadb_option_guard "$1"' _ "$file"
    [ "$status" -ne 0 ]
}
