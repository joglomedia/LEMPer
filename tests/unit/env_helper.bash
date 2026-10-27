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
