#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Stack - Security Update Bootstrap                                |
# |-------------------------------------------------------------------------|
# | Installs the latest LEMPer CLI and updater plugin on an existing        |
# | legacy installation, then patches PHP2Shell (CVE-2026-109618 /          |
# | CVE-2026-109619) and the rest of the stack through the package          |
# | manager.                                                                |
# |-------------------------------------------------------------------------|
# | Copyright (c) 2014-2026 MasEDI.Net (https://masedi.net/lemper)          |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@lemper.cloud so we can send you a copy immediately.          |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <me@masedi.net>                                |
# +-------------------------------------------------------------------------+

set -e -o pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
ORIGINAL_ARGS=("$@")

CLI_BIN="/usr/local/bin/lemper-cli"
CLI_ALIAS="/usr/bin/lemper-cli"
PLUGINS_DIR="/etc/lemper/cli-plugins"
CONFIG_FILE="/etc/lemper/lemper.conf"
UPDATE_SOURCE_FILE="/etc/lemper/update-source"

MODE="install-and-update"
UPDATE_SUBCOMMAND="all"
UPDATE_ARGS=()

RED=31
GREEN=32
YELLOW=33

function begin_color() {
    echo -e -n "\e[${1}m"
}

function end_color() {
    echo -e -n "\e[0m"
}

function info() {
    begin_color "${YELLOW}"
    echo -n "Info: "
    end_color
    echo "$@"
}

function success() {
    begin_color "${GREEN}"
    echo -n "Success: "
    end_color
    echo "$@"
}

function error() {
    begin_color "${RED}"
    echo -n "Error: " >&2
    end_color
    echo "$@" >&2
}

function warning() {
    begin_color "${YELLOW}"
    echo -n "Warning: " >&2
    end_color
    echo "$@" >&2
}

function fail() {
    error "$@"
    exit 1
}

function show_help() {
    cat <<EOF
LEMPer security update bootstrap

Usage: sudo ./update.sh [mode] [options]

Modes:
  (default)             Install the updater, then run 'lemper-cli update all'.
  --install-only        Install the CLI and updater plugin, change nothing else.
  --check               Install the updater, then report exposure only.
  --help                Show this help.

Options:
  --source-dir=PATH     LEMPer checkout used for CLI/plugin updates.
                        Defaults to this script's directory.
  --post-max-size=SIZE  post_max_size for EOL PHP mitigations (default: 32M).
  -y, --yes             Unattended mode (service restarts are automatic).

The default run reinstalls everything scripts/install_tools.sh installs
(CLI, plugins, Adminer, the file manager, and the PHP admin panels), then
patches PHP, nginx, and MariaDB. --install-only reinstalls those tools and
does not change stack packages. --check installs the updater and audits
exposure; it does not reinstall the tools.

The updater patches PHP 8.2.35+, 8.3.36+, 8.4.27+ and 8.5.12+ from the
configured apt repositories. EOL PHP branches receive admin-locked
compensating controls in every FPM pool and are reported as requiring
migration; they cannot be fully fixed by this script.
EOF
}

function requires_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        if ! command -v sudo >/dev/null 2>&1; then
            fail "This script must be run as root (or install sudo)."
        fi
        info "Switching to root to install the LEMPer updater..."
        exec sudo -E "$0" "$@"
    fi
}

function check_prerequisites() {
    command -v apt-get >/dev/null 2>&1 || fail "apt-get not found; LEMPer updates require Debian/Ubuntu."
}

function install_updater() {
    local source_dir="${1:-${BASE_DIR}}"

    [[ -f "${source_dir}/bin/lemper-cli.sh" && -f "${source_dir}/lib/lemper-update.sh" ]] ||
        fail "No usable LEMPer checkout at ${source_dir} (need bin/lemper-cli.sh and lib/lemper-update.sh)."

    info "Installing LEMPer CLI from ${source_dir}..."
    install -m 0755 "${source_dir}/bin/lemper-cli.sh" "${CLI_BIN}"
    ln -sfn "${CLI_BIN}" "${CLI_ALIAS}"

    install -d -m 0700 /etc/lemper "${PLUGINS_DIR}"
    chmod 0700 /etc/lemper "${PLUGINS_DIR}" 2>/dev/null || true
    install -m 0755 "${source_dir}/lib/lemper-update.sh" "${PLUGINS_DIR}/lemper-update"

    printf '%s\n' "${source_dir}" > "${UPDATE_SOURCE_FILE}"
    chmod 0600 "${UPDATE_SOURCE_FILE}"

    success "Updater installed. Re-run 'lemper-cli update all' at any time."
}

function run_updater() {
    [[ -f "${CONFIG_FILE}" ]] || fail "No LEMPer configuration at ${CONFIG_FILE}; this host does not look like a LEMPer installation."

    # Encrypted configs are decrypted with /etc/lemper/.config_key by the CLI.
    if head -n 1 "${CONFIG_FILE}" | grep -q '^Salted__'; then
        export ENCRYPT_CONFIG_AT_REST=true
    fi

    info "Running: lemper-cli update ${UPDATE_SUBCOMMAND} ${UPDATE_ARGS[*]:-}"
    "${CLI_BIN}" update "${UPDATE_SUBCOMMAND}" "${UPDATE_ARGS[@]}"
}

export PROG_NAME="${PROG_NAME:-lemper-cli}"
export LEMPER_UPDATE_LIB_ONLY=true
# shellcheck source=lib/lemper-update.sh
. "${BASE_DIR}/lib/lemper-update.sh"

# Argument parsing.
PARSED_ARGS=()
UPDATE_SOURCE_DIR=""
while [[ $# -gt 0 ]]; do
    case "${1}" in
        --install-only)
            MODE="install-only"
            shift
            ;;
        --check)
            UPDATE_SUBCOMMAND="check"
            shift
            ;;
        --source-dir=*)
            UPDATE_SOURCE_DIR="${1#*=}"
            shift
            ;;
        --post-max-size=*)
            UPDATE_ARGS+=("${1}")
            shift
            ;;
        -y | --yes)
            UPDATE_ARGS+=("${1}")
            shift
            ;;
        -h | --help)
            show_help
            exit 0
            ;;
        *)
            PARSED_ARGS+=("${1}")
            shift
            ;;
    esac
done

if [[ "${#PARSED_ARGS[@]}" -gt 0 ]]; then
    fail "Unknown option: ${PARSED_ARGS[0]} (use --help)"
fi

requires_root "${ORIGINAL_ARGS[@]}"
check_prerequisites
install_updater "${UPDATE_SOURCE_DIR:-${BASE_DIR}}"
UPDATE_SOURCE_DIR="${UPDATE_SOURCE_DIR:-${BASE_DIR}}"

case "${MODE}" in
    install-only)
        update_lemper_tooling
        info "Administration tools reinstalled. Stack packages were not changed."
        ;;
    install-and-update)
        run_updater
        ;;
esac
