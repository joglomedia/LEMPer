##
# Shared setup for LEMPer unit tests.
#
# Points BASE_DIR at an isolated temp directory containing a copy of
# .env.dist, so sourcing scripts/utils.sh never touches the repository's
# working tree.
##

unit_setup() {
    export REAL_BASE_DIR="${BATS_TEST_DIRNAME}/../.."
    export TEST_TMPDIR="${BATS_TEST_TMPDIR}"
    mkdir -p "${TEST_TMPDIR}"
    cp "${REAL_BASE_DIR}/.env.dist" "${TEST_TMPDIR}/.env"
    export BASE_DIR="${TEST_TMPDIR}"
    export LEMPER_CORE_DIR="${REAL_BASE_DIR}/lib/core"
    export LEMPER_OPERATION_LOCK="${TEST_TMPDIR}/operation.lock"
    export DRYRUN=false
}

# Skip tests that need GNU getopt (the DB CLI parses long options with it).
require_gnu_getopt() {
    local rc=0
    getopt --test >/dev/null 2>&1 || rc=$?
    if [[ "${rc}" -ne 4 ]]; then
        skip "GNU getopt is required"
    fi
}

# Hosted checkouts may have private ancestors. Stage only public code for nobody;
# keep the runner home and credential-bearing test directories unchanged.
test_run_public() (
    local source="$1" entry="$2" public file
    shift 2
    [[ "$entry" != /* && "$entry" != *..* && -f "$source/$entry" ]] || return 1
    public=$(mktemp -d /var/tmp/lemper-public-XXXXXXXX) || return 1
    trap 'rm -rf -- "$public"' EXIT
    mkdir "$public/bin" "$public/lib" || return 1
    while IFS= read -r -d '' file; do
        install -D -m 0644 "$file" "$public/${file#"$source/"}" || return 1
    done < <(find "$source/bin" "$source/lib" -type f -name '*.sh' -print0)
    for file in install.sh remove.sh update.sh lemper.sh; do
        [[ ! -f "$source/$file" ]] || cp "$source/$file" "$public/" || return 1
    done
    local -a environment=(env -u BASH_ENV "LEMPER_CORE_DIR=$public/lib/core")
    if [[ -n "${LEMPER_COVERAGE_SOURCE:-}" ]]; then
        mkdir "$public/tests" || return 1
        cp "$LEMPER_COVERAGE_SOURCE/tests/coverage_hook.bash" "$public/tests/" || return 1
        environment+=("BASH_ENV=$public/tests/coverage_hook.bash")
    fi
    find "$public" -type d -exec chmod 0755 {} + || return 1
    find "$public" -type f -exec chmod 0644 {} + || return 1
    runuser -u nobody -- "${environment[@]}" bash "$public/$entry" "$@"
)
