#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Shared Security Helpers                                          |
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

##
# Show site list help.
##
function site_list_show_usage() {
    cat <<-EOL
${CMD_PARENT} ${CMD_NAME} list

Lists all configured virtual hosts on this server.

Usage:
  ${CMD_PARENT} ${CMD_NAME} list [OPTIONS]

Options:
  -j, --json      Output as JSON instead of table.
  -a, --all       Show all vhosts including disabled ones (default).
  -e, --enabled   Show only enabled vhosts (symlinked in sites-enabled).
  -d, --disabled  Show only disabled vhosts (no symlink in sites-enabled).
  -h, --help      Print this message and exit.
  -v, --version   Output version information and exit.

For more informations visit https://masedi.net/lemper
Mail bug reports and suggestions to <me@masedi.net>
EOL
}

##
# Main App
##
function init_lemper_site_list() {
    if [[ -n "${1}" ]]; then
        list_vhosts "$@"
    else
        site_list_show_usage
    fi
}
