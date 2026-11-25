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



function lemper_service_control() {
    local action="$1" unit="$2" version
    if [[ "$action" == status ]]; then
        systemctl --no-pager status "$unit"
        return $?
    fi
    # A dry run must not execute even a service's configuration validator.
    if [[ "${DRYRUN:-false}" != true ]]; then
        case "$action:$unit" in
            reload:nginx|restart:nginx) nginx -t || return 1 ;;
            reload:php*-fpm|restart:php*-fpm)
                version="${unit#php}"; version="${version%-fpm}"
                "php-fpm$version" -t || return 1 ;;
        esac
    fi
    lemper_exec systemctl "$action" "$unit"
}
