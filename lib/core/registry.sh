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



# Static registries are shared by packaging, dispatch, help and recipes.
function lemper_command_plugins() {
    cat <<'REGISTRY'
lemper-account:lemper-account
lemper-adduser:lemper-adduser
lemper-site:lemper-site
lemper-site-list:lemper-site-list
lemper-site-show:lemper-site-show
lemper-create:lemper-site-create
lemper-manage:lemper-site-update
lemper-db:lemper-db
lemper-selfssl:lemper-selfssl
lemper-fixpermission:lemper-fixpermission
lemper-bench:lemper-bench
lemper-modsec:lemper-modsec
lemper-tui:lemper-tui
lemper-stack:lemper-stack
lemper-mail:lemper-mail
lemper-update:lemper-update
lemper-backup:lemper-backup
lemper-data:lemper-data
lemper-monitor:lemper-monitor
lemper-firewall:lemper-firewall
lemper-hosting:lemper-hosting
REGISTRY
}

function lemper_command_aliases() {
    cat <<'REGISTRY'
lemper-site-add:lemper-site-create
lemper-site-mod:lemper-site-update
lemper-site-manage:lemper-site-update
lemper-create:lemper-site-create
lemper-add:lemper-site-create
lemper-manage:lemper-site-update
lemper-mod:lemper-site-update
lemper-site-db:lemper-db
lemper-site-database:lemper-db
REGISTRY
}

function lemper_component_ids() {
    printf '%s\n' nginx php mariadb redis valkey postgres memcached mongodb \
        pureftpd vsftpd crowdsec fail2ban certbot bun mailer modsec imagemagick tools restic monit nftables quota
}
function lemper_component_spec() {
    case "${1}" in
        phalcon) echo 'phalcon - - INSTALL_PHP_PHALCON php' ;;
        pure-ftpd) lemper_component_spec pureftpd ;;
        nginx) echo 'nginx nginx nginx INSTALL_NGINX nginx' ;;
        php) echo 'php php PHP INSTALL_PHP php' ;;
        mariadb|mysql) echo 'mariadb mariadb mariadb INSTALL_MYSQL mariadb' ;;
        redis) echo 'redis redis redis-server INSTALL_REDIS redis' ;;
        valkey) echo 'redis redis valkey-server INSTALL_REDIS valkey' ;;
        postgres|postgresql) echo 'postgres postgres postgresql INSTALL_POSTGRES postgresql' ;;
        memcached) echo 'memcached memcached memcached INSTALL_MEMCACHED memcached' ;;
        mongodb) echo 'mongodb mongodb mongod INSTALL_MONGODB mongodb' ;;
        pureftpd) echo 'pureftpd pureftpd pure-ftpd INSTALL_FTP_SERVER pure-ftpd' ;;
        vsftpd) echo 'vsftpd vsftpd vsftpd INSTALL_FTP_SERVER vsftpd' ;;
        ftp) lemper_component_spec "${FTP_SERVER_NAME:-pureftpd}" ;;
        crowdsec) echo 'crowdsec crowdsec crowdsec INSTALL_CROWDSEC crowdsec' ;;
        fail2ban) echo 'fail2ban fail2ban fail2ban INSTALL_FAIL2BAN fail2ban' ;;
        certbot) echo 'certbotle certbotle certbot.timer INSTALL_CERTBOT certbot' ;;
        bun) echo 'bun bun - INSTALL_BUNJS bun' ;;
        mailer) echo 'mailer mailer postfix,dovecot INSTALL_MAILER postfix' ;;
        modsec) echo 'modsec modsec nginx INSTALL_MODSEC libmodsecurity' ;;
        imagemagick) echo 'imagemagick imagemagick - INSTALL_IMAGEMAGICK imagemagick' ;;
        restic) echo 'restic restic - INSTALL_RESTIC restic' ;;
        monit) echo 'monit monit lemper-monit INSTALL_MONITORING monit' ;;
        nftables) echo 'nftables nftables lemper-nftables INSTALL_FW nftables' ;;
        quota) echo 'quota quota - INSTALL_QUOTA quota' ;;
        tools) echo 'tools tools - - -' ;;
        *) error "Unknown stack service: ${1}"; return 1 ;;
    esac
}

# Ordered recipes refer to the same canonical component IDs as stack commands.
function lemper_component_recipe() {
    case "$1" in
        install) printf '%s\n' certbot nginx php phalcon mariadb postgres redis mongodb \
            memcached imagemagick mailer ftp fail2ban crowdsec modsec tools bun restic monit quota ;;
        remove) printf '%s\n' nginx mariadb postgres php imagemagick redis valkey mongodb memcached mailer \
            pureftpd vsftpd fail2ban crowdsec modsec certbot bun restic monit quota ;;
        *) return 1 ;;
    esac
}

# id|label|installation capability|wizard visibility|required project files
# Manual types retain generic PHP vhost support; no installer is advertised.
function lemper_site_application_registry() {
    cat <<'APPLICATIONS'
default|Vanilla PHP|none|true|-
wordpress|WordPress|automatic|true|wp-includes/class-wp.php,index.php
wordpress-ms|WordPress Multisite|automatic|true|wp-includes/class-wp.php,index.php
laravel|Laravel|automatic|true|artisan,public/index.php
symfony|Symfony|automatic|true|src/Kernel.php,public/index.php
codeigniter|CodeIgniter|automatic|true|spark,public/index.php
drupal|Drupal|automatic|true|core/lib/Drupal.php,index.php
phalcon|Phalcon|automatic|true|app/config/config.php
roundcube|Roundcube|automatic|true|public_html/index.php,program/include/rcmail.php,vendor/autoload.php
mautic|Mautic|automatic|true|index.php,bin/console,app/AppKernel.php,vendor/autoload.php
sendy|Sendy|manual|true|-
owncloud|ownCloud|automatic|false|occ,index.php
lumen|Lumen|automatic|false|artisan,public/index.php
woocommerce|WooCommerce|automatic|false|wp-includes/class-wp.php,wp-content/plugins/woocommerce/woocommerce.php
phalcon-cli|Phalcon CLI|automatic|false|app/config/config.php
phalcon-micro|Phalcon Micro|automatic|false|app/config/config.php
phalcon-modules|Phalcon Modules|automatic|false|app/config/config.php
snappymail|SnappyMail|automatic|true|index.php,_include.php
nextcloud|Nextcloud|automatic|true|index.php,occ,lib/versioncheck.php,3rdparty/autoload.php
mybb|MyBB|automatic|true|index.php,inc/init.php,install/index.php
phplist|phpList|automatic|true|public_html/lists/index.php,public_html/lists/admin/index.php,vendor/autoload.php
xenforo|XenForo|manual|true|-
ojs|Open Journal Systems|automatic|true|index.php,config.TEMPLATE.inc.php,lib/pkp/lib/vendor/autoload.php
slim|Slim Framework|automatic|true|public/index.php,vendor/autoload.php
APPLICATIONS
}
