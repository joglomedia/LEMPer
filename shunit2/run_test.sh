#!/bin/bash

# First example from https://github.com/kward/shunit2

#script_under_test=$(basename "$0")

# Source the helper functions.
if [[ -f ./scripts/utils.sh ]]; then
    . ./scripts/utils.sh
    preflight_system_check
    init_log
    init_config
else
    echo "Helper function (scripts/utils.sh) not found."
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

testTrueInstallCertbot()
{
    . scripts/install_certbotle.sh

    #certbot_bin=$(command -v certbot)
    #assertEquals "/usr/bin/certbot" "${certbot_bin}"
    cb=$(command -v certbot | grep -c certbot)
    assertTrue "[[ ${cb} -gt 0 ]]"
}

testTrueInstallFTPServer()
{
    if [[ "${FTP_SERVER_NAME}" == "pureftpd" || "${FTP_SERVER_NAME}" == "pure-ftpd" ]]; then
        if [ -f scripts/install_pureftpd.sh ]; then
            . scripts/install_pureftpd.sh
        fi

        ftps=$(command -v pure-ftpd | grep -c pure-ftpd)
        assertTrue "[[ ${ftps} -gt 0 ]]"
    else
        if [ -f scripts/install_vsftpd.sh ]; then
            . scripts/install_vsftpd.sh
        fi

        ftps=$(command -v vsftpd | grep -c vsftpd)
        assertTrue "[[ ${ftps} -gt 0 ]]"
    fi
}

testTrueInstallNginx()
{
    . scripts/install_nginx.sh

    #nginx_bin=$(command -v nginx)
    #assertEquals "/usr/sbin/nginx" "${nginx_bin}"
    ngx=$(command -v nginx | grep -c nginx)
    assertTrue "[[ ${ngx} -gt 0 ]]"
}

testEqualityInstallMySQL()
{
    . scripts/install_mariadb.sh

    mysql_bin=$(command -v mysql)
    assertEquals "/usr/bin/mysql" "${mysql_bin}"

    mysqld_bin=$(command -v mysqld)
    assertEquals "/usr/sbin/mysqld" "${mysqld_bin}"
}

testEqualityInstallPhp()
{
    . scripts/install_php.sh

    php_bin=$(command -v php)
    assertEquals "/usr/bin/php" "${php_bin}"
}

testTrueInstallImageMagick()
{
    . scripts/install_imagemagick.sh

    mgk=$(command -v magick | grep -c magick)

    if [[ ${mgk} -gt 0 ]]; then
        assertTrue "[[ ${mgk} -gt 0 ]]"
    fi

    cvt=$(command -v convert | grep -c convert)

    if [[ ${cvt} -gt 0 ]]; then
        assertTrue "[[ ${cvt} -gt 0 ]]"
    fi
}

testEqualityInstallMemcached()
{
    . scripts/install_memcached.sh

    memcached_bin=$(command -v memcached)
    assertEquals "/usr/bin/memcached" "${memcached_bin}"
}

testEqualityInstallRedis()
{
    . scripts/install_redis.sh

    rediscli_bin=$(command -v redis-cli)
    assertEquals "/usr/bin/redis-cli" "${rediscli_bin}"

    redisserver_bin=$(command -v redis-server)
    assertEquals "/usr/bin/redis-server" "${redisserver_bin}"
}

#testEqualityInstallMongoDB()
# {
#    . scripts/install_mongodb.sh

#    mongo_bin=$(command -v mongo)
#    assertEquals "/usr/bin/mongo" "${mongo_bin}"

#    mongod_bin=$(command -v mongod)
#    assertEquals "/usr/bin/mongod" "${mongod_bin}"
#}

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
    assertTrue "[[ -d /etc/lemper/cli-plugins ]]"
}

testEqualityCreateNewVhost()
{
    sudo /usr/local/bin/lemper-cli create -d lemper.test -f wordpress -i
    assertTrue "[[ -f /etc/nginx/sites-available/lemper.test.conf ]]"
}

# load shunit2
. /usr/local/bin/shunit2
