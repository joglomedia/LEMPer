#!/usr/bin/env bash

# ImageMagick Installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 17/07/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellchechk source=scripts/helper.sh
    # shellcheck disable=SC1090
    . "${BASEDIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

function init_imagemagick_install {
    if "${AUTO_INSTALL}"; then
        INSTALL_IMAGEMAGICK="y"
    fi
    while [[ "${INSTALL_IMAGEMAGICK}" != "y" && "${INSTALL_IMAGEMAGICK}" != "n" ]]; do
        read -rp "Do you want to install ImageMagick library? [y/n]: " -i y -e INSTALL_IMAGEMAGICK
    done
    if [[ "${INSTALL_IMAGEMAGICK}" == y* && "${PHP_IMAGEMAGICK}" == true ]]; then
        echo "Installing ImageMagick library from source..."

        run wget -q https://www.imagemagick.org/download/ImageMagick.tar.gz
        run tar xf ImageMagick.tar.gz
        run cd ImageMagick-*
        run ./configure
        run make
        run make install
        run ldconfig /usr/local/lib
        run cd ../
        run rm -fr ImageMagick-*

        if "${DRYRUN}"; then
            warning "ImageMagick installed in dryrun mode."
        else
            if [[ -z $(command -v magick) ]]; then
                status "ImageMagick version $(magick -version |grep ^Version | cut -d' ' -f3) has been installed."
            elif [[ -z $(command -v identify) ]]; then
                status "ImageMagick version $(identify -version |grep ^Version | cut -d' ' -f3) has been installed."
            fi
        fi
    else
        warning "ImageMagick installation skipped..."
    fi
}

echo "[Welcome to ImageMagick Installer]"
echo ""

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v magick) || -n $(command -v identify) ]]; then
    warning "ImageMagick already exists. Installation skipped..."
else
    init_imagemagick_install "$@"
fi
