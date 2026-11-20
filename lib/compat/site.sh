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

# Legacy functions may exit. Each operation gets its own subshell.
function lemper_legacy_site_action() {
    local action="$1" domain="$2" handler root
    case "$action" in
        enable) lemper_nginx_site_set_enabled "$domain" true; return $? ;;
        disable) lemper_nginx_site_set_enabled "$domain" false; return $? ;;
        ssl-enable) handler=enable_ssl ;;
        ssl-disable) handler=disable_ssl ;;
        ssl-remove) handler=remove_ssl ;;
        ssl-renew) handler=renew_ssl ;;
        fastcgi-cache-enable) handler=enable_fastcgi_cache ;;
        fastcgi-cache-disable) handler=disable_fastcgi_cache ;;
        cors-enable) handler=enable_cors ;;
        cors-disable) handler=disable_cors ;;
        fail2ban-enable) handler=enable_fail2ban ;;
        fail2ban-disable) handler=disable_fail2ban ;;
        modsec-enable) handler=enable_modsec ;;
        modsec-disable) handler=disable_modsec ;;
        brotli-enable) handler=enable_brotli ;;
        gzip-enable) handler=enable_gzip ;;
        compression-disable) handler=disable_compression ;;
        *) return 1 ;;
    esac
    root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd) || return 1
    (
        export LEMPER_MANAGE_LIB_ONLY=true
        # Legacy plugin is linted independently.
        # shellcheck source=/dev/null
        . "$root/lemper-manage.sh" || exit 1
        # The parent validates and reloads once after the batch.
        # shellcheck disable=SC2329 # Called indirectly by legacy action functions.
        function reload_nginx() { return 0; }
        "$handler" "$domain"
    )
}
function lemper_legacy_site_create() {
    local root
    root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd) || return 1
    (
        # Plugin dispatcher guard is satisfied by the public bootstrap.
        # shellcheck source=/dev/null
        . "$root/lemper-create.sh" "$@"
    )
}
