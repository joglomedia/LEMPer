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

echo "Installing Administration tools..."

# Install Nginx vHost Creator
run cp -f scripts/ngxvhost.sh /usr/local/bin/ngxvhost
run cp -f scripts/ngxtool.sh /usr/local/bin/ngxtool
run chmod ugo+x /usr/local/bin/ngxvhost
run chmod ugo+x /usr/local/bin/ngxtool

# Install Web-viewer Tools
run mkdir /usr/share/nginx/html/tools/

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
run wget --no-check-certificate https://raw.github.com/rlerdorf/opcache-status/master/opcache.php -O /usr/share/nginx/html/tools/opcache.php

# Install Memcache Web-based stats
#http://blog.elijaa.org/index.php?pages/phpMemcachedAdmin-Installation-Guide
run git clone https://github.com/elijaa/phpmemcachedadmin.git /usr/share/nginx/html/tools/phpMemcachedAdmin/

# Install Adminer for Web-based MySQL Administration Tool
run mkdir /usr/share/nginx/html/tools/adminer/
run wget --no-check-certificate https://github.com/vrana/adminer/releases/download/v4.7.1/adminer-4.7.1.php -O /usr/share/nginx/html/tools/adminer/index.php
run wget --no-check-certificate https://github.com/vrana/adminer/releases/download/v4.7.1/editor-4.7.1.php -O /usr/share/nginx/html/tools/adminer/editor.php

# Install FileRun File Manager
run mkdir /usr/share/nginx/html/tools/filerun/
run wget -O FileRun.zip http://www.filerun.com/download-latest
run unzip FileRun.zip -d /usr/share/nginx/html/tools/filerun/
run rm -f FileRun.zip

if [[ -x /usr/local/bin/ngxvhost && -x /usr/local/bin/ngxtool && -d /usr/share/nginx/html/tools ]]; then
    status "Web administration tools successfully installed."
fi
