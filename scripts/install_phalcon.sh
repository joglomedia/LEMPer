#!/usr/bin/env bash

# Phalcon & Zephir Installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 23/08/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.2.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellchechk source=scripts/helper.sh
    # shellcheck disable=SC1090
    . "${BASEDIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

function init_phalcon_install() {
    local PHPv=${1:-$PHP_VERSION}

    # Define build directory.
    BUILD_DIR=${BUILD_DIR:-"/usr/local/src/lemper"}
    if [ ! -d "${BUILD_DIR}" ]; then
        run mkdir -p "${BUILD_DIR}"
    fi

    # Install prerequisite packages.
    run apt-get install -y gcc libpcre3-dev make re2c autoconf automake

    # Install Zephir from source.
    while [[ $INSTALL_ZEPHIR != "y" && $INSTALL_ZEPHIR != "n" ]]; do
        read -rp "Install Zephir Interpreter? [y/n]: " -e INSTALL_ZEPHIR
    done

    if [[ "$INSTALL_ZEPHIR" == Y* || "$INSTALL_ZEPHIR" == y* ]]; then
        # Install Zephir parser.
        run git clone -q git://github.com/phalcon/php-zephir-parser.git "${BUILD_DIR}/php-zephir-parser"
        run pushd "${BUILD_DIR}/php-zephir-parser"

        if [[ -n "${PHPv}" ]]; then
            run "phpize${PHPv}"
            run ./configure --with-php-config="/usr/bin/php-config${PHPv}"
        else
            run phpize
            run ./configure
        fi

        run make
        run make install
        run popd

        # Install Zephir.
        ZEPHIR_BRANCH=$(git ls-remote https://github.com/phalcon/zephir 0.12.* | sort -t/ -k3 -Vr | head -n1 | awk -F/ '{ print $NF }')
        run git clone --depth 1 --branch "${ZEPHIR_BRANCH}" -q https://github.com/phalcon/zephir.git "${BUILD_DIR}/zephir"
        run pushd "${BUILD_DIR}/zephir"
        # install zephir
        run composer install
        run popd
    fi

    # Install cPhalcon from source.
    run git clone --depth=1 --branch=3.4.x -q https://github.com/phalcon/cphalcon.git "${BUILD_DIR}/cphalcon"
    run pushd "${BUILD_DIR}/cphalcon/build"

    if [[ -n "${PHPv}" ]]; then
        run ./install --phpize "/usr/bin/phpize${PHPv}" --php-config "/usr/bin/php-config${PHPv}"
    else
        run ./install
    fi

    run popd
}

echo "[welcome to Phalcon PHP Framework Installer]"
echo ""

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
PHP_VERSION=${1:-$PHP_VERSION}
if [[ -n $(command -v "php${PHP_VERSION}") ]]; then
    if "php${PHP_VERSION}" --ri phalcon | grep -qwE "phalcon => enabled"; then
        warning "Phalcon PHP already installed. Installation skipped..."
    else
        init_phalcon_install "$@"
    fi
fi
