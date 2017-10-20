#!/usr/bin/env bash

echo "Installing addon tools..."

# Install Nginx Vhost Creator
cp -f scripts/ngxvhost.sh /usr/local/bin/ngxvhost
cp -f scripts/ngxvhost.sh /usr/local/bin/ngxrmvhost
chmod ugo+x /usr/local/bin/ngxvhost
chmod ugo+x /usr/local/bin/ngxrmvhost

# Install Web-viewer Tools
mkdir /usr/share/nginx/html/tools/

# Install Zend OpCache Web Viewer
wget --no-check-certificate https://raw.github.com/rlerdorf/opcache-status/master/opcache.php -O /usr/share/nginx/html/tools/opcache.php

# Install Memcache Web-based stats
#http://blog.elijaa.org/index.php?pages/phpMemcachedAdmin-Installation-Guide
git clone https://github.com/elijaa/phpmemcachedadmin.git /usr/share/nginx/html/tools/phpMemcachedAdmin/

# Install Adminer for Web-based MySQL Administration Tool
mkdir /usr/share/nginx/html/tools/adminer/
wget --no-check-certificate https://github.com/vrana/adminer/releases/download/v4.3.1/adminer-4.3.1.php -O /usr/share/nginx/html/tools/adminer/index.php
wget --no-check-certificate https://github.com/vrana/adminer/releases/download/v4.3.1/editor-4.3.1.php -O /usr/share/nginx/html/tools/adminer/editor.php

# Install PHP Info
cat > /usr/share/nginx/html/tools/phpinfo.php <<EOL
<?php phpinfo(); ?>
EOL

cat > /usr/share/nginx/html/tools/phpinfo.php70 <<EOL
<?php phpinfo(); ?>
EOL

cat > /usr/share/nginx/html/tools/phpinfo.php71 <<EOL
<?php phpinfo(); ?>
EOL
