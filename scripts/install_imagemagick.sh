#!/usr/bin/env bash

# Include decorator
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    . ${BASEDIR}/decorator.sh
fi

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    error "This script must be run as root..."
    exit 1
fi

echo "Installing ImageMagick from source..."

run wget -q https://www.imagemagick.org/download/ImageMagick.tar.gz
run tar xf ImageMagick.tar.gz
run cd ImageMagick-7*
./configure
run make
run make install
run ldconfig /usr/local/lib

run rm -fr ImageMagick-7*

if [ -n "$(magick -version |grep -o 'Version: ImageMagic *')" ]; then
    status "ImageMagic version $(magick -version |grep ^Version | cut -d' ' -f3) has been installed"
elif [ -n "$(identify -version |grep -o 'Version: ImageMagic *')" ]; then
    status "ImageMagic version $(identify -version |grep ^Version | cut -d' ' -f3) has been installed"
fi
