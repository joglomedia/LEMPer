#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Security & Stack Updater                                   |
# +-------------------------------------------------------------------------+
# | Patches PHP2Shell (CVE-2026-109618 / CVE-2026-109619) and keeps the     |
# | rest of the stack current. Supported branches are upgraded from apt.    |
# | --migrate-to=VERSION moves EOL vhosts onto that PHP and creates any     |
# | missing FPM pool. Without it, EOL pools get compensating controls.      |
# |                                                                         |
# | Invoked as: lemper-cli update <check|php|nginx|mariadb|lemper|all>      |
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

CMD_PARENT="${PROG_NAME}"
CMD_NAME="update"
export CMD_PARENT CMD_NAME

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

lemper_load_module runtime/stack/update || return 1
lemper_load_module services/php/update || return 1
lemper_load_module services/php/migrate || return 1
lemper_load_module services/nginx/repository || return 1
lemper_load_module services/nginx/update || return 1
lemper_load_module services/mariadb/update || return 1
lemper_load_module services/tools/update || return 1
lemper_update_initialize

if [[ "${LEMPER_UPDATE_LIB_ONLY:-false}" != true ]]; then
    init_lemper_update "$@"
fi
