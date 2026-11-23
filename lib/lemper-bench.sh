#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Hardware, Disk, and Network Benchmark                      |
# +-------------------------------------------------------------------------+
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

# shellcheck disable=SC2034
CMD_PARENT="${PROG_NAME}"
# shellcheck disable=SC2034
CMD_NAME="bench"

# Make sure only root can access and not direct access.
if [[ "$(type -t requires_root)" != "function" ]]; then
    echo "Direct access to this script is not permitted."
    exit 1
fi

# Load shared argument/validation helpers when this plugin is sourced in isolation.
if ! declare -F lemper_parse_args >/dev/null; then
    PLUGIN_SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    if [[ -f "${PLUGIN_SOURCE_DIR}/core/loader.sh" ]]; then
        # The dispatcher provides core helpers; isolated loading is covered by core lint/tests.
        # shellcheck source=/dev/null
        . "${PLUGIN_SOURCE_DIR}/core/loader.sh" || return 1
    else
        # The dispatcher provides core helpers; isolated loading is covered by core lint/tests.
        # shellcheck source=/dev/null
        . "${PLUGIN_SOURCE_DIR}/../core/loader.sh" || return 1
    fi
fi

export CMD_PARENT CMD_NAME
lemper_load_module runtime/benchmark/commands || return 1
lemper_load_module services/system/benchmark || return 1
lemper_bench_initialize

if [[ "${LEMPER_BENCH_LIB_ONLY:-false}" != true ]]; then
    init_lemper_bench "$@"
fi
