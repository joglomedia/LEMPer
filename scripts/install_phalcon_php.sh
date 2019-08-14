#!/usr/bin/env bash

# Phalcon PHP extension installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 13/11/2015
# Author            : MasEDI.Net (hi@masedi.net)

# Make sure only root can run this installer script
if [ "$(id -u)" -ne 0 ]; then
    echo "You need to be root to run this script"
    exit 1
fi

cat <<- _EOF_
#========================================================================#
#      PhalconPHP Installer for Ubuntu Server, Written by ESLabs.ID      #
#========================================================================#
#   A small tool to install PhalconPHP Framework & Zephir Interpreter    #
#                                                                        #
#       For more information please visit https://eslabs.id/lemper       #
#========================================================================#
_EOF_

# Prerequisite packages
apt-get install re2c libpcre3-dev gcc make

# Install Zephir
while [[ $INSTALL_ZEPHIR != "y" && $INSTALL_ZEPHIR != "n" ]]; do
    read -p "Install Zephir Interpreter? [y/n]: " -e INSTALL_ZEPHIR
done

if [[ "$INSTALL_ZEPHIR" == Y* || "$INSTALL_ZEPHIR" == y* ]]; then
    # clon Zephir repo
    git clone -q https://github.com/phalcon/zephir.git
    cd zephir

    # install json-c
    ./install-json

    # install zephir
    composer install
    ./install
fi

git clone -q http://github.com/phalcon/cphalcon.git
git checkout master
cd cphalcon/build
./install
