#!/bin/bash

# First example from https://github.com/kward/shunit2

script_under_test=$(basename "$0")

# Nginx versions.
nginx_stable_version="1.21.0"
nginx_latest_version="1.20.1"

# Source the helper functions.
if [ -f scripts/helper.sh ]; then
    source scripts/helper.sh
    preflight_system_check
    init_log
    init_config
else
    echo "Helper function (scripts/helper.sh) not found."
    exit 1
fi

testEqualityGetDistribName()
{
    distrib_name=$(get_distrib_name)
    assertEquals "ubuntu" "${distrib_name}"
}

testEqualityGetReleaseName()
{
    release_name=$(get_release_name)
    assertEquals "focal" "${release_name}"
}

testEqualityCreateAccount()
{
    create_account_status=""
    create_account lemper
    [[ -n $(getent passwd "${USERNAME}") ]] && create_account_status="success"
    assertEquals "success" "${create_account_status}"
}

testEqualityInstallCertbot()
{
    . scripts/install_certbotle.sh

    certbot_bin=$(command -v certbot)
    assertEquals "/usr/bin/certbot" "${certbot_bin}"
}

testEqualityInstallNginx()
{
    . scripts/install_nginx.sh

    nginx_bin=$(command -v nginx)
    assertEquals "/usr/sbin/nginx" "${nginx_bin}"
}

testEqualityInstallPhp()
{
    . scripts/install_php.sh

    php_bin=$(command -v php)
    assertEquals "/usr/bin/php" "${php_bin}"
}

testTrueInstallPhpLoader()
{
    . scripts/install_phploader.sh

    ic=$(php7.4 -v | grep -c ionCube)
    assertTrue "[[ ${ic} -gt 0 ]]"

    #g=$(php7.4 -v | grep -c SourceGuardian)
    #assertTrue "[ ${sg} -gt 0 ]"
}

testEqualityInstallPhpImageMagick()
{
    . scripts/install_imagemagick.sh

    imagick_bin=$(command -v identify)
    assertEquals "/usr/bin/identify" "${imagick_bin}"
}

testEqualityInstallMySQL()
{
    . scripts/install_mariadb.sh

    mysql_bin=$(command -v mysql)
    assertEquals "/usr/bin/mysql" "${mysql_bin}"

    mysqld_bin=$(command -v mysqld)
    assertEquals "/usr/sbin/mysqld" "${mysqld_bin}"
}

testEqualityInstallRedis()
{
    . scripts/install_redis.sh

    rediscli_bin=$(command -v redis-cli)
    assertEquals "/usr/bin/redis-cli" "${rediscli_bin}"

    redisserver_bin=$(command -v redis-server)
    assertEquals "/usr/bin/redis-server" "${redisserver_bin}"
}

testEqualityInstallMongoDB()
{
    . scripts/install_mongodb.sh

    mongo_bin=$(command -v mongo)
    assertEquals "/usr/bin/mongo" "${mongo_bin}"

    mongod_bin=$(command -v mongod)
    assertEquals "/usr/bin/mongod" "${mongod_bin}"
}

testEqualityInstallFail2ban()
{
    . scripts/install_fail2ban.sh

    fail2ban_bin=$(command -v fail2ban-server)
    assertEquals "/usr/local/bin/fail2ban-server" "${fail2ban_bin}"
}

testEqualityInstallTools()
{
    . scripts/install_tools.sh
    assertTrue "[[ -x /usr/local/bin/lemper-cli ]]"
}

testEqualityCreateNewVhost()
{
    sudo /usr/local/bin/lemper-cli create -d lemper.local -f wordpress -i
    assertTrue "[[ -f /etc/nginx/sites-available/lemper.local.conf ]]"
}

# load shunit2
. /usr/local/bin/shunit2
