#!/usr/bin/env bats
##
# Test helper for LEMPer bats suite.
#
# Sets up environment so that validation functions can be sourced and tested
# on both macOS (BSD grep) and Linux (GNU grep).
#

setup() {
    export BASE_DIR="${BATS_TEST_DIRNAME}/.."
}

teardown() {
    # Clean up any test .env symlink we may have created.
    if [[ -L "${BASE_DIR}/.env" ]]; then
        rm -f "${BASE_DIR}/.env" "${BASE_DIR}/.env.test"
    fi
}

# Source utils.sh with a .env file present.
# utils.sh requires BASE_DIR/.env; we create it from .env.dist.
load_utils() {
    if [[ ! -f "${BASE_DIR}/.env" ]]; then
        cp "${BASE_DIR}/.env.dist" "${BASE_DIR}/.env.test"
        ln -sf "${BASE_DIR}/.env.dep" "${BASE_DIR}/.env" 2>/dev/null || true
        ln -sf "${BASE_DIR}/.env.dist" "${BASE_DIR}/.env"
    fi
    # shellcheck source=scripts/utils.sh
    . "${BASE_DIR}/scripts/utils.sh"
}
