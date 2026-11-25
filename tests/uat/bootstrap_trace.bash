#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer UAT Bootstrap Location Diagnostics                               |
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

# Explicit UAT instrumentation: descriptor 19 records locations and exit status.
# Never include BASH_COMMAND, expansions, arguments or configuration values.
# dpkg closes inherited descriptors in maintainer scripts. Do not instrument
# those child shells when the UAT log descriptor is unavailable.
if [[ "${LEMPER_UAT_BOOTSTRAP_TRACE:-false}" == true ]] && { : >&19; } 2>/dev/null; then
    set -T
    trap 'printf "%s:%s:%s:%s\n" "${BASH_SOURCE[0]:-}" "${LINENO}" "${FUNCNAME[0]:-}" "$?" >&19' DEBUG
fi
