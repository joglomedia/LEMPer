#!/bin/bash

# First example from https://github.com/kward/shunit2

script_under_test=$(basename "$0")

# Nginx
nginx_stable_version="1.16.1"
nginx_latest_version="1.17.6"

# Source the helper functions.
if [ -f scripts/helper.sh ]; then
    source scripts/helper.sh
    init_log
    init_config
else
    echo "Helper function (scripts/helper.sh) not found."
    exit 1
fi

testEquality()
{
    assertEquals 1 1
}

testEqualityGetDistribName()
{
    distrib_name=$(get_distrib_name)
    assertEquals "ubuntu" "${distrib_name}"
}

testEqualityGetReleaseName()
{
    release_name=$(get_release_name)
    assertEquals "bionic" "${release_name}"
}

testEqualityCreateAccount()
{
    release_name=$(create_account lemper)
    assertEquals "Username lemper created." "${release_name}"
}

testEqualityGetNginxStableVersion()
{
    ngx_stable_version=$(determine_stable_nginx_version)
    assertEquals "${nginx_stable_version}" "${ngx_stable_version}"
}

testEqualityGetNginxLatestVersion()
{
    ngx_latest_version=$(determine_latest_nginx_version)
    assertEquals "${nginx_latest_version}" "${ngx_latest_version}"
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

testEqualityInstallMySQL()
{
    . scripts/install_mariadb.sh

    mysql_bin=$(command -v mysql)
    assertEquals "/usr/bin/mysql" "${mysql_bin}"

    mysqld_bin=$(command -v mysqld)
    assertEquals "/usr/sbin/mysqld" "${mysqld_bin}"
}

# load shunit2
. /usr/local/bin/shunit2
