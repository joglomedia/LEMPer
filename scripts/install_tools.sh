#!/usr/bin/env bash

# Include decorator
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    . ${BASEDIR}/decorator.sh
fi

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    error "This script must be run as root..."
    exit 1
fi

echo -e "\nInstalling web administration tools...\n"

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
<p>If you see this page, the nginx web server is successfully installed using LEMPer. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
LEMPer and ngxTools support is available at
<a href="https://github.com/joglomedia/LEMPer/issues">LEMPer git</a>.</p>

<p><em>Thank you for using nginx, ngxTools, and LEMPer.</em></p>

<p style="font-size:90%;">Generated using <em>LEMPer</em> from <a href="https://eslabs.id/lemper">Nginx vHost Tool</a>, a simple nginx web server management tool.</p>
</body>
</html>
_EOF_
}

# Install Nginx vHost Creator
run cp -f scripts/ngxvhost.sh /usr/local/bin/ngxvhost
run cp -f scripts/ngxtool.sh /usr/local/bin/ngxtool
run chmod ugo+x /usr/local/bin/ngxvhost
run chmod ugo+x /usr/local/bin/ngxtool

# Install Web-viewer Tools
run mkdir /usr/share/nginx/html/tools/

create_index_file > /usr/share/nginx/html/index.html
create_index_file > /usr/share/nginx/html/tools/index.html

# Install PHP Info
#cat > /usr/share/nginx/html/tools/phpinfo.php <<EOL
#<?php phpinfo(); ?>
#EOL
run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/tools/phpinfo.php'
run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/tools/phpinfo.php70'
run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/tools/phpinfo.php71'
run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/tools/phpinfo.php72'
run bash -c 'echo "<?php phpinfo(); ?>" > /usr/share/nginx/html/tools/phpinfo.php73'

# Install Zend OpCache Web Viewer
run wget -q --no-check-certificate https://raw.github.com/rlerdorf/opcache-status/master/opcache.php -O /usr/share/nginx/html/tools/opcache.php

# Install Memcache Web-based stats
#http://blog.elijaa.org/index.php?pages/phpMemcachedAdmin-Installation-Guide
run git clone https://github.com/elijaa/phpmemcachedadmin.git /usr/share/nginx/html/tools/phpMemcachedAdmin/

# Install Adminer for Web-based MySQL Administration Tool
run mkdir /usr/share/nginx/html/tools/adminer/
run wget -q --no-check-certificate https://github.com/vrana/adminer/releases/download/v4.7.1/adminer-4.7.1.php -O /usr/share/nginx/html/tools/adminer/index.php
run wget -q --no-check-certificate https://github.com/vrana/adminer/releases/download/v4.7.1/editor-4.7.1.php -O /usr/share/nginx/html/tools/adminer/editor.php

# Install FileRun File Manager
run mkdir /usr/share/nginx/html/tools/filerun/
run wget -q http://www.filerun.com/download-latest -O FileRun.zip
run unzip -qq FileRun.zip -d /usr/share/nginx/html/tools/filerun/
run rm -f FileRun.zip

# TODO: try Tinyfilemanager https://github.com/prasathmani/tinyfilemanager

# Assign ownership properly
run chown -hR www-data:root /usr/share/nginx/html/tools/

# Create new default username
echo -e "\nCreating default Linux account..."

if [[ -z $(getent passwd lemper) ]]; then
    katasandi=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
    run useradd -d /home/lemper -m -s /bin/bash lemper
    echo "lemper:${katasandi}" | chpasswd
    run usermod -aG sudo lemper

    if [ -d /home/lemper ]; then
        run mkdir /home/lemper/webapps
        run chown -hR lemper:lemper /home/lemper/webapps
    fi
fi

if [[ -x /usr/local/bin/ngxvhost && -x /usr/local/bin/ngxtool && -d /usr/share/nginx/html/tools ]]; then
    status -e "\nWeb administration tools successfully installed.\n"
fi
