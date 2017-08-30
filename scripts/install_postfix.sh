#!/usr/bin/env bash

# Install Postfix mail server
apt-get install -y mailutils postfix

# Update local time
apt-get install -y ntpdate
ntpdate -d cn.pool.ntp.org
