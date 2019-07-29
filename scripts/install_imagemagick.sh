#!/usr/bin/env bash

# ImageMagic Installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 17/07/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    . ${BASEDIR}/helper.sh
fi

# Make sure only root can run this installer script
if [ "$(id -u)" -ne 0 ]; then
    error "You need to be root to run this script"
    exit 1
fi

echo "Installing ImageMagick from source..."

run wget -q https://www.imagemagick.org/download/ImageMagick.tar.gz
run tar xf ImageMagick.tar.gz
run cd ImageMagick-7*
run ./configure
run make
run make install
run ldconfig /usr/local/lib
run rm -fr ImageMagick-7*

if "${DRYRUN}"; then
    status "ImageMagic installed in dryrun mode."
else
    if [ -n "$(magick -version |grep -o 'Version: ImageMagic *')" ]; then
        status "ImageMagic version $(magick -version |grep ^Version | cut -d' ' -f3) has been installed."
    elif [ -n "$(identify -version |grep -o 'Version: ImageMagic *')" ]; then
        status "ImageMagic version $(identify -version |grep ^Version | cut -d' ' -f3) has been installed."
    fi
fi
