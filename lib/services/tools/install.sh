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
        printf '%s\n' "$BASE_DIR" >/etc/lemper/update-source || return 1
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
            && run git config --global --add safe.directory /usr/share/nginx/html/lcp/memcadmin \
            && run git pull -q \
            && run cd "${CURRENT_DIR}" || return 1
    fi

    # Configure phpMemcachedAdmin.
    # A tools refresh that only has .env.dist must not replace a live SASL
    # config with the sample credentials.
    if [[ "${DRYRUN}" != true && "${LEMPER_TOOLS_PRESERVE_ADMIN_CONFIG:-false}" == true && -f /usr/share/nginx/html/lcp/memcadmin/Config/Memcache.php ]]; then
        info "Keeping the existing phpMemcachedAdmin configuration."
    elif [[ "${DRYRUN}" != true ]]; then
        if [[ ${MEMCACHED_SASL} == "enable" || ${MEMCACHED_SASL} == true ]]; then
            MEMCACHED_SASL_CREDENTIAL="username=${MEMCACHED_USERNAME},
            password=${MEMCACHED_PASSWORD},"
        else
            MEMCACHED_SASL_CREDENTIAL=""
        fi

        run touch /usr/share/nginx/html/lcp/memcadmin/Config/Memcache.php
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
    'file_path' => 'Temp/',
    'servers' =>
    [
        'LEMPer Stack' =>
        [
            '127.0.0.1:11211' =>
            [
                'hostname' => '127.0.0.1',
                'port' => '11211',
                ${MEMCACHED_SASL_CREDENTIAL}
            ],
            '127.0.0.1:11212' =>
            [
                'hostname' => '127.0.0.1',
                'port' => '11212',
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
            && run cp includes/config.sample.inc.php includes/config.inc.php

        if [[ "${REDIS_REQUIRE_PASSWORD}" == true ]]; then
            sed_inplace "s|//'auth'\ =>\ 'redispasswordhere'|'auth'\ =>\ '${REDIS_PASSWORD}'|g" includes/config.inc.php
        fi
    else
        run cd redisadmin \
            && run mv composer.lock composer.lock~
        run "${COMPOSER_BIN}" -q update
    fi

    run cd "${CURRENT_DIR}" || return 1
    [ -f /usr/share/nginx/html/lcp/redisadmin/index.php ] && echo_ok "OK"

    # Assign ownership properly.
    run chown -hR www-data:www-data /usr/share/nginx/html

    if [[ -x /usr/local/bin/lemper-cli && -d /usr/share/nginx/html/lcp ]]; then
        success "LEMPer CLI & web tools successfully installed."
    fi
}

function lemper_tools_install_entry() {
    echo "[LEMPer CLI & Web Tools Installation]"
    init_tools_install "$@"
}
