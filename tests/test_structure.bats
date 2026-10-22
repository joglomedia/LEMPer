#!/usr/bin/env bats
##
# Bats test suite for LEMPer architecture structure.
#
# These tests verify that the refactoring (Phase 2 Task 11) was done correctly:
# - install.sh and remove.sh are thin wrappers
# - lemper.sh sources shared lemper_stacks.sh instead of inline functions
# - lemper_stacks.sh contains the shared lemper_install() and lemper_remove()
#

setup() {
    export BASE_DIR="${BATS_TEST_DIRNAME}/.."
}

@test "install.sh is a thin wrapper that sources lemper_stacks.sh" {
    # install.sh should NOT contain inline lemper_install function body
    local inline_count
    inline_count=$(grep -c 'function lemper_install()' "${BASE_DIR}/install.sh" 2>/dev/null || true)
    [ "${inline_count}" -eq 0 ]

    # install.sh should source lemper-stacks.sh from lib/core/
    grep -q 'lib/core/lemper-stacks.sh' "${BASE_DIR}/install.sh"

    # install.sh should call lemper_install
    grep -q 'lemper_install' "${BASE_DIR}/install.sh"
}

@test "install.sh calls requires_root and preflight before install" {
    grep -q 'requires_root' "${BASE_DIR}/install.sh"
    grep -q 'preflight_system_check' "${BASE_DIR}/install.sh"
    grep -q 'header_msg' "${BASE_DIR}/install.sh"
    grep -q 'footer_msg' "${BASE_DIR}/install.sh"
}

@test "remove.sh is a thin wrapper that sources lemper_stacks.sh" {
    # remove.sh should NOT contain inline lemper_remove function body
    local inline_count
    inline_count=$(grep -c 'function lemper_remove()' "${BASE_DIR}/remove.sh" 2>/dev/null || true)
    [ "${inline_count}" -eq 0 ]

    # remove.sh should source lemper-stacks.sh from lib/core/
    grep -q 'lib/core/lemper-stacks.sh' "${BASE_DIR}/remove.sh"

    # remove.sh should call lemper_remove
    grep -q 'lemper_remove' "${BASE_DIR}/remove.sh"
}

@test "remove.sh calls requires_root and preflight before remove" {
    grep -q 'requires_root' "${BASE_DIR}/remove.sh"
    grep -q 'preflight_system_check' "${BASE_DIR}/remove.sh"
    grep -q 'header_msg' "${BASE_DIR}/remove.sh"
    grep -q 'footer_msg' "${BASE_DIR}/remove.sh"
}

@test "lemper.sh sources lemper_stacks.sh instead of inline functions" {
    # lemper.sh should NOT contain inline lemper_install or lemper_remove
    local install_count remove_count
    install_count=$(grep -c 'function lemper_install()' "${BASE_DIR}/lemper.sh" 2>/dev/null || true)
    remove_count=$(grep -c 'function lemper_remove()' "${BASE_DIR}/lemper.sh" 2>/dev/null || true)
    [ "${install_count}" -eq 0 ]
    [ "${remove_count}" -eq 0 ]

    # lemper.sh should source lemper_stacks.sh from lib/core/
    grep -q 'lib/core/lemper-stacks.sh' "${BASE_DIR}/lemper.sh"
}

@test "lemper_stacks.sh contains lemper_install function" {
    grep -q 'function lemper_install()' "${BASE_DIR}/lib/core/lemper-stacks.sh"
}

@test "lemper_stacks.sh contains lemper_remove function" {
    grep -q 'function lemper_remove()' "${BASE_DIR}/lib/core/lemper-stacks.sh"
}

@test "lemper.sh preserves CLI argument parsing (init_lemper_install)" {
    grep -q 'init_lemper_install' "${BASE_DIR}/lemper.sh"
}

@test "lemper.sh preserves getopt-based CLI flags" {
    grep -q 'getopt' "${BASE_DIR}/lemper.sh"
    grep -q 'install' "${BASE_DIR}/lemper.sh"
    grep -q 'remove' "${BASE_DIR}/lemper.sh"
}
