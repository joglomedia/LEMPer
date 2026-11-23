#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | Nginx Self-Signed SSL Certificate                                       |
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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script should be sourced, not executed directly."
    exit 1
fi

if [[ "$(type -t lemper_load_module)" != function ]]; then
    NGINX_COMPAT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd) || return 1
    # shellcheck source=/dev/null
    . "$NGINX_COMPAT_ROOT/lib/core/loader.sh" || return 1
fi
lemper_load_module services/nginx/tls || return 1
