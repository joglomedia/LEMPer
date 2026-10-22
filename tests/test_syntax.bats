#!/usr/bin/env bats
##
# Bats test suite for LEMPer script syntax verification.
#
# These tests verify that all shell scripts parse correctly with `bash -n`
# (syntax check only — no execution), and pass ShellCheck with -x (follow includes).
#

setup() {
    export BASE_DIR="${BATS_TEST_DIRNAME}/.."
}

# Collect all .sh files that should be syntax-validated.
_get_script_files() {
    echo "${BASE_DIR}/install.sh"
    echo "${BASE_DIR}/remove.sh"
    echo "${BASE_DIR}/lemper.sh"
    echo "${BASE_DIR}/bin/lemper-cli.sh"
    for f in "${BASE_DIR}"/lib/lemper-*.sh; do
        echo "${f}"
    done
    for f in "${BASE_DIR}"/lib/core/*.sh; do
        echo "${f}"
    done
    for f in "${BASE_DIR}"/scripts/*.sh; do
        echo "${f}"
    done
    for f in "${BASE_DIR}"/scripts/nginx/*.sh; do
        echo "${f}"
    done
}

@test "all scripts pass bash syntax check (bash -n)" {
    local result=0
    while IFS= read -r script; do
        if ! bash -n "${script}" 2>/dev/null; then
            echo "SYNTAX ERROR in ${script}" >&2
            bash -n "${script}" >&2 2>&1
            result=1
        fi
    done < <(_get_script_files)
    [ "${result}" -eq 0 ]
}

@test "all scripts pass shellcheck -s bash -x" {
    local result=0
    while IFS= read -r script; do
        if ! shellcheck -s bash -x "${script}" 2>/dev/null; then
            echo "SHELLCHECK FAIL in ${script}" >&2
            shellcheck -s bash -x "${script}" >&2 2>&1
            result=1
        fi
    done < <(_get_script_files)
    [ "${result}" -eq 0 ]
}
