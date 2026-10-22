#!/usr/bin/env bash
#
# Run LEMPer validation suite inside a Podman container.
# This is the recommended way for macOS developers to test Linux-targeted scripts.
#
# Usage:
#   ./scripts/test_podman.sh              # Run all tests
#   ./scripts/test_podman.sh --lint       # Run ShellCheck only
#   ./scripts/test_podman.sh --test       # Run bats tests only
#   ./scripts/test_podman.sh --dry-run    # Run install.sh in dry-run mode
#
# Prerequisites:
#   - Podman with a running machine: podman machine start
#   - Project root must be accessible via volume mount

set -euo pipefail

# Resolve project root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MODE="${1:-all}"
IMAGE="${TEST_IMAGE:-ubuntu:24.04}"
VOLUME="${PROJECT_ROOT}:/lemper:ro"
WORKDIR="/lemper"

# Base setup command for installing tools in the container.
SETUP="apt-get update -qq && apt-get install -qq -y shellcheck bats > /dev/null 2>&1"

# ShellCheck command — mirrors CI.
SC_CMD="shellcheck -s bash -x \
    install.sh remove.sh lemper.sh \
    bin/lemper-cli.sh \
    lib/lemper-*.sh lib/core/lemper-stacks.sh \
    scripts/install_*.sh scripts/remove_*.sh scripts/utils.sh \
    scripts/server_*.sh scripts/nginx/*.sh \
    tests/*.bats"

# Bats command.
BATS_CMD="bats tests/"

case "${MODE}" in
    --lint)
        echo "=== Running ShellCheck in ${IMAGE} ==="
        podman run --rm \
            -v "${VOLUME}" \
            -w "${WORKDIR}" \
            "${IMAGE}" bash -c "${SETUP} && ${SC_CMD}"
        ;;
    --test)
        echo "=== Running bats tests in ${IMAGE} ==="
        podman run --rm \
            -v "${VOLUME}" \
            -w "${WORKDIR}" \
            "${IMAGE}" bash -c "${SETUP} && ${BATS_CMD}"
        ;;
    --dry-run)
        echo "=== Running install.sh dry-run in ${IMAGE} ==="
        # Use rw volume for dry-run since install.sh may attempt writes.
        podman run --rm --privileged \
            -v "${PROJECT_ROOT}:/lemper:rw" \
            -w "${WORKDIR}" \
            "${IMAGE}" bash -c "
                apt-get update -qq && \
                cp .env.dist .env && \
                sed -i 's/AUTO_INSTALL=false/AUTO_INSTALL=true/' .env && \
                sed -i 's/INSTALL_NGINX=true/INSTALL_NGINX=false/' .env && \
                sed -i 's/INSTALL_PHP=true/INSTALL_PHP=false/' .env && \
                DRYRUN=true bash install.sh
            "
        ;;
    all|"")
        echo "=== Running full validation in ${IMAGE} ==="
        podman run --rm \
            -v "${VOLUME}" \
            -w "${WORKDIR}" \
            "${IMAGE}" bash -c "
                ${SETUP} && \
                echo '--- ShellCheck ---' && \
                ${SC_CMD} && \
                echo '--- Bats Tests ---' && \
                ${BATS_CMD} && \
                echo '✅ All checks passed'
            "
        ;;
    *)
        echo "Usage: $0 [--lint|--test|--dry-run]"
        echo "  (no args)  = run all checks (ShellCheck + bats)"
        echo "  --lint     = run ShellCheck only"
        echo "  --test     = run bats tests only"
        echo "  --dry-run  = run install.sh in dry-run mode"
        exit 1
        ;;
esac
