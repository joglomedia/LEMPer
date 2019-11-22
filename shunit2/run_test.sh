#!/bin/bash

# First example from https://github.com/kward/shunit2

script_under_test=$(basename "$0")

if [ -f "./scripts/helper.sh" ]; then
    . ./scripts/helper.sh
else
    echo "Helper function (scripts/helper.sh) not found."
    exit 1
fi

testEquality()
{
    assertEquals 1 1
}

testEqualityGetReleaseName()
{
    distro_name=$(get_release_name)
    assertEquals "bionic" "${distro_name}"
}

testEqualityGetNginxStableVersion()
{
    ngx_stable_version=$(determine_stable_nginx_version)
    assertEquals "1.16.1" "${ngx_stable_version}"
}

testEqualityGetNginxLatestVersion()
{
    ngx_latest_version=$(determine_latest_nginx_version)
    assertEquals "1.17.6" "${ngx_latest_version}"
}

# load shunit2
. /usr/local/bin/shunit2
