#!/usr/bin/env bash

# LEMPer administration installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 04/10/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellchechk source=scripts/helper.sh
    # shellcheck disable=SC1090
    . "${BASEDIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

function init_webadmin_install() {
    # Install Lemper CLI tool.
    echo "Installing Lemper CLI tool..."
    run cp -f bin/lemper-cli.sh /usr/local/bin/lemper-cli
    run chmod ugo+x /usr/local/bin/lemper-cli

    if [ ! -d /usr/local/lib/lemper ]; then
        run mkdir -p /usr/local/lib/lemper
    fi

    run cp -f lib/lemper-create.sh /usr/local/lib/lemper/lemper-create
    run cp -f lib/lemper-manage.sh /usr/local/lib/lemper/lemper-manage
    run chmod ugo+x /usr/local/lib/lemper/lemper-create
    run chmod ugo+x /usr/local/lib/lemper/lemper-manage

    # Install Web Admin.
    echo "Installing Lemper web panel..."
    if [ ! -d /usr/share/nginx/html/lcp ]; then
        run mkdir -p /usr/share/nginx/html/lcp
    fi

    # Copy default index file.
    run cp -f share/nginx/html/index.html /usr/share/nginx/html/

    # Install PHP Info
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php56'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php70'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php71'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php72'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php73'

    # Install Adminer for Web-based MySQL Administration Tool
    if [ ! -d /usr/share/nginx/html/lcp/dbadmin ]; then
        run mkdir -p /usr/share/nginx/html/lcp/dbadmin
        run wget -q https://github.com/vrana/adminer/releases/download/v4.7.3/adminer-4.7.3.php \
            -O /usr/share/nginx/html/lcp/dbadmin/index.php
        run wget -q https://github.com/vrana/adminer/releases/download/v4.7.3/editor-4.7.3.php \
            -O /usr/share/nginx/html/lcp/dbadmin/editor.php
    fi

    # Install File Manager
    # Experimental: Replace FileRun with Tinyfilemanager https://github.com/PHPlayground/tinyfilemanager
    if [ ! -d /usr/share/nginx/html/lcp/filemanager ]; then
        #run mkdir -p /usr/share/nginx/html/lcp/filemanager
        #run wget -q http://www.filerun.com/download-latest -O /usr/share/nginx/html/lcp/FileRun.zip && \
        #run unzip -o -qq /usr/share/nginx/html/lcp/FileRun.zip -d /usr/share/nginx/html/lcp/filemanager && \
        #run rm -f /usr/share/nginx/html/lcp/FileRun.zip

        # Clone custom TinyFileManager.
        if [ ! -d /usr/share/nginx/html/lcp/filemanager/config ]; then
            run git clone -q --depth=1 --branch=lemperfm_1.3.0 https://github.com/PHPlayground/tinyfilemanager.git \
                /usr/share/nginx/html/lcp/filemanager
        else
            local CUR_DIR && \
            CUR_DIR=$(pwd)
            run cd /usr/share/nginx/html/lcp/filemanager/
            run git pull -q
            run cd "${CUR_DIR}"
        fi

        # Copy TinyFileManager custom account creator.
        if [ -f /usr/share/nginx/html/lcp/filemanager/adduser-tfm.sh ]; then
            run cp -f /usr/share/nginx/html/lcp/filemanager/adduser-tfm.sh /usr/local/lib/lemper/lemper-tfm
            run chmod ugo+x /usr/local/lib/lemper/lemper-tfm
        fi
    fi

    # Install Zend OpCache Web Admin
    run wget -q https://raw.github.com/rlerdorf/opcache-status/master/opcache.php \
        -O /usr/share/nginx/html/lcp/opcache.php

    # Install Memcached Web Admin
    #http://blog.elijaa.org/index.php?pages/phpMemcachedAdmin-Installation-Guide
    if [ ! -d /usr/share/nginx/html/lcp/memcadmin/ ]; then
        run git clone -q --depth=1 --branch=master \
            https://github.com/elijaa/phpmemcachedadmin.git /usr/share/nginx/html/lcp/memcadmin/
    else
        local CUR_DIR && \
        CUR_DIR=$(pwd)
        run cd /usr/share/nginx/html/lcp/memcadmin/
        run git pull -q
        run cd "${CUR_DIR}"
    fi

    # Configure phpMemcachedAdmin.
    if ! ${DRYRUN}; then
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

    # Assign ownership properly
    run chown -hR www-data:www-data /usr/share/nginx/html

    if [[ -x /usr/local/bin/lemper-cli && -d /usr/share/nginx/html/lcp ]]; then
        status "Web administration tools successfully installed."
    fi
}

echo "[LEMPer CLI & Panel Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_webadmin_install "$@"
