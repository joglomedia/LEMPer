#!/usr/bin/env bash

# LEMPer administration installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 01/07/2019
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

function create_index_file() {
    cat <<- _EOF_
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed using
LEMPer. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
LEMPer and ngxTools support is available at
<a href="https://github.com/joglomedia/LEMPer/issues">LEMPer git</a>.</p>

<p><em>Thank you for using nginx, ngxTools, and LEMPer.</em></p>

<p style="font-size:90%;">Generated using <em>LEMPer</em> from
<a href="https://eslabs.id/lemper">Nginx vHost Tool</a>, a simple nginx web
server management tool.</p>
</body>
</html>
_EOF_
}

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

    if ! "${DRYRUN}"; then
        if [ -d /usr/share/nginx/html ]; then
            run touch /usr/share/nginx/html/index.html
            run create_index_file > /usr/share/nginx/html/index.html
        fi

        if [ -d /usr/share/nginx/html/lcp ]; then
            run touch /usr/share/nginx/html/lcp/index.html
            run create_index_file > /usr/share/nginx/html/lcp/index.html
        fi
    fi

    # Install PHP Info
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php56'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php70'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php71'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php72'
    run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/lcp/phpinfo.php73'

    # Install Adminer for Web-based MySQL Administration Tool
    if [ ! -d /usr/share/nginx/html/lcp/dbadminer ]; then
        run mkdir /usr/share/nginx/html/lcp/dbadminer
        run wget -q --no-check-certificate https://github.com/vrana/adminer/releases/download/v4.7.2/adminer-4.7.2.php \
            -O /usr/share/nginx/html/lcp/dbadminer/index.php
        run wget -q --no-check-certificate https://github.com/vrana/adminer/releases/download/v4.7.2/editor-4.7.2.php \
            -O /usr/share/nginx/html/lcp/dbadminer/editor.php
    fi

    # Install FileRun File Manager
    if [ ! -d /usr/share/nginx/html/lcp/filemanager ]; then
        run mkdir /usr/share/nginx/html/lcp/filemanager
        run wget -q http://www.filerun.com/download-latest -O /usr/share/nginx/html/lcp/FileRun.zip
        run unzip -o -qq /usr/share/nginx/html/lcp/FileRun.zip -d /usr/share/nginx/html/lcp/filemanager
        run rm -f /usr/share/nginx/html/lcp/FileRun.zip
    fi

    # TODO: Replace FileRun with Tinyfilemanager https://github.com/prasathmani/tinyfilemanager

    # Install Zend OpCache Web Admin
    run wget -q --no-check-certificate https://raw.github.com/rlerdorf/opcache-status/master/opcache.php \
        -O /usr/share/nginx/html/lcp/opcache.php

    # Install Memcached Web Admin
    #http://blog.elijaa.org/index.php?pages/phpMemcachedAdmin-Installation-Guide
    if [ ! -d /usr/share/nginx/html/lcp/phpMemcachedAdmin/ ]; then
        run git clone -q https://github.com/elijaa/phpmemcachedadmin.git /usr/share/nginx/html/lcp/phpMemcachedAdmin/
    else
        #local CUR_DIR && \
        #CUR_DIR=$(pwd)
        run pushd /usr/share/nginx/html/lcp/phpMemcachedAdmin/
        run git pull
        run popd
        #run cd "${CUR_DIR}"
    fi

    # Assign ownership properly
    run chown -hR www-data: /usr/share/nginx/html

    if [[ -x /usr/local/bin/lemper-cli && -d /usr/share/nginx/html/lcp ]]; then
        status "Web administration tools successfully installed."
    fi
}

echo "[Welcome to LEMPer Tools Installer]"
echo ""

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_webadmin_install "$@"
