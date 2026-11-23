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

# Render only validated, newly deployed complete packages; generic vhosts retain
# their compatibility renderer when automatic installation is not requested.
function lemper_site_release_render() {
    local type="$1" domain="$2" project="$3" owner="$4" php="$5" root entries setup script template directory fragment extra_mime='' index='index index.php index.html;' security='include /etc/nginx/includes/rules_security.conf;'
    is_valid_domain "$domain" && is_valid_username "$owner" && [[ "$php" =~ ^8\.[2-5]$ ]] || return 1
    lemper_site_release_target "$project" "$owner" || return 1
    case "$type" in
        mautic)
            root="$project"
            entries='index'
            setup='^/(index\.php/)?installer(/|$)'
            script=index.php
            ;;
        roundcube)
            root="$project/public_html"
            entries='index|static'
            setup='^/installer\.php$'
            script=installer.php
            ;;
        snappymail | nextcloud | mybb | phplist | ojs | slim | xenforo)
            root="$project"
            [[ "$type" != phplist ]] || root="$project/public_html/lists"
            [[ "$type" != slim ]] || root="$project/public"
            if [[ "$type" == nextcloud ]]; then
                security=''
                index=''
                grep -Eq '[[:space:]]mjs[[:space:];]' /etc/nginx/mime.types 2>/dev/null || extra_mime+='text/javascript mjs; '
                grep -Eq '[[:space:]]wasm[[:space:];]' /etc/nginx/mime.types 2>/dev/null || extra_mime+='application/wasm wasm; '
                [[ -z "$extra_mime" ]] || extra_mime="types { $extra_mime }"
            fi
            directory=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../etc/nginx/vhost" && pwd) || return 1
            fragment="$directory/apps/$type.conf"
            [[ -f "$fragment" ]] || return 1
            sed -e "/@APP_RULES@/r $fragment" -e '/@APP_RULES@/d' "$directory/site_application.conf" \
                | sed -e "s/@DOMAIN@/$domain/g" -e "s/@ROOT@/$(sanitize_sed_replacement "$root")/g" \
                    -e "s/@OWNER@/$owner/g" -e "s/@PHP@/$php/g" \
                    -e "s/@SECURITY@/$(sanitize_sed_replacement "$security")/g" -e "s/@INDEX@/$index/g" \
                    -e "s/@EXTRA_MIME@/$(sanitize_sed_replacement "$extra_mime")/g"
            local render_status=("${PIPESTATUS[@]}")
            [[ "${render_status[0]}" == 0 && "${render_status[1]}" == 0 ]]
            return $?
            ;;
        *) return 1 ;;
    esac
    template=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../etc/nginx/vhost" && pwd)/site_release.conf
    sed -e "s/@DOMAIN@/$domain/g" -e "s/@TYPE@/$type/g" \
        -e "s/@ROOT@/$(sanitize_sed_replacement "$root")/g" \
        -e "s/@OWNER@/$owner/g" -e "s/@PHP@/$php/g" \
        -e "s/@ENTRIES@/$(sanitize_sed_replacement "$entries")/g" \
        -e "s/@SETUP@/$(sanitize_sed_replacement "$setup")/g" \
        -e "s/@SETUP_SCRIPT@/$script/g" "$template"
}
