#!/usr/bin/env bash

# LEMPer administration installer
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 12/02/2022
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/utils.sh"

    # Make sure only root can run this installer script.
    requires_root "$@"

    # Make sure only supported distribution can run this installer script.
    preflight_system_check
fi

##
# LEMPer CLI & web admin install.
##
function init_tools_install() {
    # Install Lemper CLI tool.
    echo -n "Installing LEMPer CLI tool..."

    run cp -f bin/lemper-cli.sh /usr/local/bin/lemper-cli && \
    run chmod ugo+x /usr/local/bin/lemper-cli && \
    run ln -sf /usr/local/bin/lemper-cli /usr/bin/lemper-cli

    [ ! -d /etc/lemper/cli-plugins ] && run mkdir -p /etc/lemper/cli-plugins

    run cp -f lib/lemper-account.sh /etc/lemper/cli-plugins/lemper-account && \
    run chmod ugo+x /etc/lemper/cli-plugins/lemper-account

    run cp -f lib/lemper-adduser.sh /etc/lemper/cli-plugins/lemper-adduser && \
    run chmod ugo+x /etc/lemper/cli-plugins/lemper-adduser

    run cp -f lib/lemper-site.sh /etc/lemper/cli-plugins/lemper-site && \
    run chmod ugo+x /etc/lemper/cli-plugins/lemper-site

    run cp -f lib/lemper-create.sh /etc/lemper/cli-plugins/lemper-site-create && \
    run chmod ugo+x /etc/lemper/cli-plugins/lemper-site-create

    [ -f /etc/lemper/cli-plugins/lemper-site-create ] && \
        run ln -fs /etc/lemper/cli-plugins/lemper-site-create /etc/lemper/cli-plugins/lemper-site-add

    run cp -f lib/lemper-manage.sh /etc/lemper/cli-plugins/lemper-site-manage && \
    run chmod ugo+x /etc/lemper/cli-plugins/lemper-site-manage

    [ -f /etc/lemper/cli-plugins/lemper-site-manage ] && \
        run ln -fs /etc/lemper/cli-plugins/lemper-site-manage /etc/lemper/cli-plugins/lemper-site-mod

    run cp -f lib/lemper-db.sh /etc/lemper/cli-plugins/lemper-db && \
    run chmod ugo+x /etc/lemper/cli-plugins/lemper-db

    [ -f /etc/lemper/cli-plugins/lemper-site-db ] && \
        run ln -fs /etc/lemper/cli-plugins/lemper-site-db /etc/lemper/cli-plugins/lemper-site-database

    run cp -f lib/lemper-selfssl.sh /etc/lemper/cli-plugins/lemper-selfssl && \
    run chmod ugo+x /etc/lemper/cli-plugins/lemper-selfssl

    run cp -f lib/lemper-fixpermission.sh /etc/lemper/cli-plugins/lemper-fixpermission && \
    run chmod ugo+x /etc/lemper/cli-plugins/lemper-fixpermission

    run cp -f lib/lemper-bench.sh /etc/lemper/cli-plugins/lemper-bench && \
    run chmod ugo+x /etc/lemper/cli-plugins/lemper-bench

    # Remove old LEMPer CLI tool.
    [ -d /usr/local/lib/lemper ] && run rm -fr /usr/local/lib/lemper/lemper-*

    # Created vhost config directory.
    [ ! -d /etc/lemper/vhost.d ] && run mkdir -p /etc/lemper/vhost.d

    [ -x /usr/local/bin/lemper-cli ] && echo_ok "OK"


    # Install Database Adminer.
    echo -n "Installing database adminer..."

    [ ! -d /usr/share/nginx/html/lcp ] && run mkdir -p /usr/share/nginx/html/lcp

    # Copy default index file.
    run cp -f share/nginx/html/index.html /usr/share/nginx/html/

    # Install PHP Info
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php70'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php71'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php72'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php73'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php74'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php80'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php81'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php82'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php83'

    # Install Adminer for Web-based MySQL Administration Tool.
    [ ! -d /usr/share/nginx/html/lcp/dbadmin ] && run mkdir -p /usr/share/nginx/html/lcp/dbadmin

    # Overwrite existing files.
    run wget -q https://github.com/vrana/adminer/releases/download/v4.8.1/adminer-4.8.1.php \
        -O /usr/share/nginx/html/lcp/dbadmin/index.php 
    run wget -q https://github.com/vrana/adminer/releases/download/v4.8.1/editor-4.8.1.php \
        -O /usr/share/nginx/html/lcp/dbadmin/editor.php

    [ -f /usr/share/nginx/html/lcp/dbadmin/index.php ] && echo_ok "OK"


    # Install File Manager.
    # Experimental: Tinyfilemanager https://github.com/joglomedia/tinyfilemanager
    # Clone custom TinyFileManager.

    echo -n "Installing file manager..."

    if [ ! -d /usr/share/nginx/html/lcp/filemanager/config ]; then
        run git clone -q --depth=1 --branch=lemperfm_1.3.0 https://github.com/joglomedia/tinyfilemanager.git \
            /usr/share/nginx/html/lcp/filemanager
    else
        local CURRENT_DIR && \
        CURRENT_DIR=$(pwd)
        run cd /usr/share/nginx/html/lcp/filemanager && \
        run wget -q https://raw.githubusercontent.com/joglomedia/tinyfilemanager/lemperfm_1.3.0/index.php \
            -O /usr/share/nginx/html/lcp/filemanager/index.php && \
        run cd "${CURRENT_DIR}" || return 1
    fi

    # Copy TinyFileManager custom account creator.
    if [ -f /usr/share/nginx/html/lcp/filemanager/adduser-tfm.sh ]; then
        run cp -f /usr/share/nginx/html/lcp/filemanager/adduser-tfm.sh /etc/lemper/cli-plugins/lemper-tfm
        run chmod ugo+x /etc/lemper/cli-plugins/lemper-tfm
    fi

    [[ -f /usr/share/nginx/html/lcp/filemanager/index.php && -x /etc/lemper/cli-plugins/lemper-tfm ]] && \
        echo_ok "OK"


    # Install Zend OpCache Web Admin.
    echo -n "Installing phpOpCacheStatus panel..."

    run wget -q https://raw.github.com/rlerdorf/opcache-status/master/opcache.php \
        -O /usr/share/nginx/html/lcp/opcache.php
    [ -f /usr/share/nginx/html/lcp/opcache.php ] && echo_ok "OK"

    # Install phpMemcachedAdmin Web Admin.
    echo -n "Installing phpMemcachedAdmin panel..."

    if [ ! -d /usr/share/nginx/html/lcp/memcadmin/ ]; then
        run git clone -q --depth=1 --branch=master \
            https://github.com/elijaa/phpmemcachedadmin.git /usr/share/nginx/html/lcp/memcadmin/
    else
        local CURRENT_DIR && \
        CURRENT_DIR=$(pwd)
        run cd /usr/share/nginx/html/lcp/memcadmin && \
        run git config --global --add safe.directory /usr/share/nginx/html/lcp/memcadmin && \
        run git pull -q && \
        run cd "${CURRENT_DIR}" || return 1
    fi

    # Configure phpMemcachedAdmin.
    if [[ "${DRYRUN}" != true ]]; then
        if [[ ${MEMCACHED_SASL} == "enable" || ${MEMCACHED_SASL} == true ]]; then
            MEMCACHED_SASL_CREDENTIAL="username=${MEMCACHED_USERNAME},
            password=${MEMCACHED_PASSWORD},"
        else
            MEMCACHED_SASL_CREDENTIAL=""
        fi

        run touch /usr/share/nginx/html/lcp/memcadmin/Config/Memcache.php
        cat > /usr/share/nginx/html/lcp/memcadmin/Config/Memcache.php <<EOL
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

    COMPOSER_BIN=$(command -v composer)

    local CURRENT_DIR && \
    CURRENT_DIR=$(pwd)
    run cd /usr/share/nginx/html/lcp || return 1

    if [ ! -f redisadmin/includes/config.inc.php ]; then
        run "${COMPOSER_BIN}" -q create-project erik-dubbelboer/php-redis-admin redisadmin && \
        run cd redisadmin && \
        run "${COMPOSER_BIN}" -q update && \
        run cp includes/config.sample.inc.php includes/config.inc.php

        if [[ "${REDIS_REQUIRE_PASSWORD}" == true ]]; then
            run sed -i "s|//'auth'\ =>\ 'redispasswordhere'|'auth'\ =>\ '${REDIS_PASSWORD}'|g" includes/config.inc.php
        fi
    else
        run cd redisadmin && \
        run mv composer.lock composer.lock~
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

echo "[LEMPer CLI & Web Tools Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_tools_install "$@"
