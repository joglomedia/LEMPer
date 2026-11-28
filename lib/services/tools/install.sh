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
# LEMPer CLI & web admin install.
##
# Only synchronize a stock single-server config or the exact file we generated from it.
function lemper_redis_panel_auth() (
    local config="$1" sample="$2" temporary redis_hex
    [[ "${DRYRUN:-false}" != true && "${REDIS_REQUIRE_PASSWORD:-true}" == true && -n "${REDIS_PASSWORD:-}" ]] || return 0
    [[ -f "$config" && -f "$sample" ]] || return 1
    local placeholder="//'auth' => 'redispasswordhere'"
    local managed="'auth' => hex2bin\\('[0-9a-f]+'\\) /\\* LEMPer \\*/"
    if ! cmp -s -- "$config" "$sample" \
        && ! sed -E "s|$managed|$placeholder|" "$config" | cmp -s -- - "$sample"; then
        info "Keeping the customized phpRedisAdmin config. Check its Redis credentials."
        return 0
    fi
    [[ "$(grep -Fc "$placeholder" "$sample")" == 1 ]] || {
        error "Unsupported phpRedisAdmin authentication template."
        return 1
    }
    temporary=$(mktemp "${config}.XXXXXXXX") || return 1
    trap 'rm -f -- "$temporary"' EXIT
    redis_hex=$(printf '%s' "$REDIS_PASSWORD" | od -An -v -tx1 | tr -d ' \n') || return 1
    [[ "$redis_hex" =~ ^([a-f0-9]{2})+$ ]] || return 1
    printf "s|%s|'auth' => hex2bin('%s') /* LEMPer */|\n" "$placeholder" "$redis_hex" \
        | sed -f - "$sample" >"$temporary" || return 1
    chgrp www-data -- "$temporary" && chmod 0640 -- "$temporary" && mv -T -- "$temporary" "$config"
)

function init_tools_install() {
    # Registry exports include legacy lemper-create/add/manage/mod/site-db/site-database
    # and lemper-site-list/site-show paths without duplicating their mappings here.
    # shellcheck source=/dev/null
    . "$BASE_DIR/lib/core/registry.sh" || return 1
    # shellcheck source=/dev/null
    . "$BASE_DIR/lib/core/deployment.sh" || return 1
    if [[ "${LEMPER_TOOLS_SKIP_CLI:-false}" != true ]]; then
        lemper_cli_snapshot "$BASE_DIR" || return 1
    fi
    if [[ "${DRYRUN:-false}" != true ]]; then
        printf '%s\n' /opt/lemper/current >/etc/lemper/update-source || return 1
        chmod 0600 /etc/lemper/update-source || return 1
    fi

    # Remove old LEMPer CLI tool.
    [ -d /usr/local/lib/lemper ] && run rm -fr /usr/local/lib/lemper/lemper-*

    # Created vhost config directory.
    [ ! -d /etc/lemper/vhost.d ] && run mkdir -p /etc/lemper/vhost.d

    [ -x /usr/local/bin/lemper-cli ] && echo_ok "OK"

    if [[ "${INSTALL_WEB_ADMIN:-true}" == false ]]; then
        success "LEMPer CLI installed; web administration panels are disabled."
        return 0
    fi

    lemper_web_tools_tree_safe || return 1

    # Install Database Adminer.

    [ ! -d /usr/share/nginx/html/lcp ] && run mkdir -p /usr/share/nginx/html/lcp

    # Copy default index file.
    run cp -f share/nginx/html/index.html /usr/share/nginx/html/

    # Install PHP Info (reachable only behind the /lcp basic-auth vhost).
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php'
    run rm -f /usr/share/nginx/html/lcp/phpinfo.php81
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php82'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php83'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php84'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php85'

    # Install Adminer for Web-based MySQL Administration Tool.
    echo -n "Installing database Adminer..."
    [ ! -d /usr/share/nginx/html/lcp/dbadmin ] && run mkdir -p /usr/share/nginx/html/lcp/dbadmin

    ADMINER_VERSION=${ADMINER_VERSION:-"6.2.0"}

    # Overwrite existing files (including leftovers from AdminerEvo installs).
    run curl -fsSL -o /usr/share/nginx/html/lcp/dbadmin/index.php \
        "https://github.com/vrana/adminer/releases/download/v${ADMINER_VERSION}/adminer-${ADMINER_VERSION}.php"
    run curl -fsSL -o /usr/share/nginx/html/lcp/dbadmin/editor.php \
        "https://github.com/vrana/adminer/releases/download/v${ADMINER_VERSION}/editor-${ADMINER_VERSION}.php"

    [ -f /usr/share/nginx/html/lcp/dbadmin/index.php ] && echo_ok "OK"

    # Install File Manager.
    # Experimental: Tinyfilemanager https://github.com/joglomedia/tinyfilemanager
    # Clone custom TinyFileManager.
    echo -n "Installing file manager TinyFileManager..."

    if [ ! -d /usr/share/nginx/html/lcp/filemanager/config ]; then
        run git clone -q --depth=1 --branch=lemperfm_1.3.0 https://github.com/joglomedia/tinyfilemanager.git \
            /usr/share/nginx/html/lcp/filemanager
    else
        local CURRENT_DIR \
            && CURRENT_DIR=$(pwd)
        run cd /usr/share/nginx/html/lcp/filemanager \
            && run curl -sSL -o /usr/share/nginx/html/lcp/filemanager/index.php \
                https://raw.githubusercontent.com/joglomedia/tinyfilemanager/lemperfm_1.3.0/index.php \
            && run cd "${CURRENT_DIR}" || return 1
    fi

    # Copy TinyFileManager custom account creator.
    if [ -f /usr/share/nginx/html/lcp/filemanager/adduser-tfm.sh ]; then
        run cp -f /usr/share/nginx/html/lcp/filemanager/adduser-tfm.sh /etc/lemper/cli-plugins/lemper-tfm
        run chmod ugo+x /etc/lemper/cli-plugins/lemper-tfm
    fi

    [[ -f /usr/share/nginx/html/lcp/filemanager/index.php && -x /etc/lemper/cli-plugins/lemper-tfm ]] \
        && echo_ok "OK"

    # Install Zend OpCache Web Admin.
    echo -n "Installing phpOpCacheStatus panel..."

    run curl -sSL -o /usr/share/nginx/html/lcp/opcache.php \
        https://raw.github.com/rlerdorf/opcache-status/master/opcache.php
    [ -f /usr/share/nginx/html/lcp/opcache.php ] && echo_ok "OK"

    # Install phpMemcachedAdmin Web Admin.
    echo -n "Installing phpMemcachedAdmin panel..."

    if [ ! -d /usr/share/nginx/html/lcp/memcadmin/ ]; then
        run git clone -q --depth=1 --branch=master \
            https://github.com/elijaa/phpmemcachedadmin.git /usr/share/nginx/html/lcp/memcadmin/
    else
        local CURRENT_DIR \
            && CURRENT_DIR=$(pwd)
        run cd /usr/share/nginx/html/lcp/memcadmin \
            && run git pull -q \
            && run cd "${CURRENT_DIR}" || return 1
    fi

    # Configure phpMemcachedAdmin.
    # Client endpoint changes are an explicit migration on existing deployments.
    if [[ "${DRYRUN}" != true && -f /usr/share/nginx/html/lcp/memcadmin/Config/Memcache.php ]]; then
        info "Keeping the existing phpMemcachedAdmin configuration."
    elif [[ "${DRYRUN}" != true ]]; then
        # The Server backend uses a text-protocol socket. The FPM user owns this
        # instance; the separate memcache instance has its own access policy.
        cat >/usr/share/nginx/html/lcp/memcadmin/Config/Memcache.php <<EOL
<?php
return [
    'stats_api' => 'Server',
    'slabs_api' => 'Server',
    'items_api' => 'Server',
    'get_api' => 'Server',
    'set_api' => 'Server',
    'delete_api' => 'Server',
    'flush_all_api' => 'Server',
    'connection_timeout' => '1',
    'max_item_dump' => '100',
    'refresh_rate' => 2.0,
    'memory_alert' => '80',
    'hit_rate_alert' => '90',
    'eviction_alert' => '0',
    'file_path' => '/var/lib/php/lemper/www-data/tmp/',
    'servers' =>
    [
        'LEMPer Stack' =>
        [
            'www-data' =>
            [
                'hostname' => 'unix:///run/lemper-memcached-www-data/memcached.sock',
                'port' => -1,
            ],
        ],
    ],
];
EOL
    fi

    [ -f /usr/share/nginx/html/lcp/memcadmin/index.php ] && echo_ok "OK"

    # Install phpRedisAdmin Web Admin.
    echo -n "Installing PhpRedisAdmin panel..."

    COMPOSER_BIN=$(command -v composer || true)

    local CURRENT_DIR \
        && CURRENT_DIR=$(pwd)
    run cd /usr/share/nginx/html/lcp || return 1

    if [ ! -f redisadmin/includes/config.inc.php ]; then
        run "${COMPOSER_BIN}" -q create-project erik-dubbelboer/php-redis-admin redisadmin \
            && run cd redisadmin \
            && run "${COMPOSER_BIN}" -q update \
            && run cp includes/config.sample.inc.php includes/config.inc.php || return 1
    else
        run cd redisadmin || return 1
        [[ ! -f composer.lock ]] || run mv composer.lock composer.lock~
        run "${COMPOSER_BIN}" -q update || return 1
    fi
    lemper_redis_panel_auth includes/config.inc.php includes/config.sample.inc.php || return 1

    run cd "${CURRENT_DIR}" || return 1
    [ -f /usr/share/nginx/html/lcp/redisadmin/index.php ] && echo_ok "OK"

    if [[ -x /usr/local/bin/lemper-cli && -d /usr/share/nginx/html/lcp ]]; then
        success "LEMPer CLI & web tools successfully installed."
    fi
}

function lemper_tools_install_entry() {
    echo "[LEMPer CLI & Web Tools Installation]"
    init_tools_install "$@"
}
