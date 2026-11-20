#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | ImageMagick Uninstaller                                                 |
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

if [[ "$(type -t run)" != function ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )
    cd "${BASE_DIR}" || exit 1
    # shellcheck source=scripts/utils.sh
    . "${BASE_DIR}/scripts/utils.sh" || exit 1
    requires_root "$@"
    preflight_system_check || exit 1
fi

if ! lemper_provisioned imagemagick && [[ "${FORCE_REMOVE:-false}" != true ]]; then
    info "Pre-existing ImageMagick is preserved; force is required for removal."
else
    if dpkg-query -W -f='${Status}' imagemagick 2>/dev/null | grep -q 'install ok installed'; then
        run apt-get purge -y imagemagick imagemagick-6-common imagemagick-6.q16
    else
        [[ ! -x /usr/local/bin/magick ]] || run rm -f /usr/local/bin/magick
    fi
fi
