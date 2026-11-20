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
lemper-update:lemper-update
lemper-backup:lemper-backup
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
        pureftpd vsftpd crowdsec fail2ban certbot bun mailer modsec imagemagick tools
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
        tools) echo 'tools tools - - -' ;;
        *) error "Unknown stack service: ${1}"; return 1 ;;
    esac
}

# Ordered recipes refer to the same canonical component IDs as stack commands.
function lemper_component_recipe() {
    case "$1" in
        install) printf '%s\n' certbot nginx php phalcon mariadb postgres redis mongodb \
            memcached imagemagick mailer ftp fail2ban crowdsec modsec tools bun ;;
        remove) printf '%s\n' nginx mariadb postgres php imagemagick redis valkey mongodb memcached mailer \
            pureftpd vsftpd fail2ban crowdsec modsec certbot bun ;;
        *) return 1 ;;
    esac
}
