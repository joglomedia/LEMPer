#!/usr/bin/env bash

# ImageMagick Installer
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 11/12/2021
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

##
# Install ImageMagick.
##
function init_imagemagick_install() {
    local SELECTED_INSTALLER=""

    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_IMAGEMAGICK}" == true ]]; then
            DO_INSTALL_IMAGEMAGICK="y"
            SELECTED_INSTALLER=${IMAGEMAGICK_INSTALLER:-"repo"}
        else
            DO_INSTALL_IMAGEMAGICK="n"
        fi
    else
        while [[ "${DO_INSTALL_IMAGEMAGICK}" != "y" && "${DO_INSTALL_IMAGEMAGICK}" != "Y" && \
            "${DO_INSTALL_IMAGEMAGICK}" != "n" && "${DO_INSTALL_IMAGEMAGICK}" != "N" ]]; do
            read -rp "Do you want to install ImageMagick library? [y/n]: " -i y -e DO_INSTALL_IMAGEMAGICK
        done
    fi

    if [[ ${DO_INSTALL_IMAGEMAGICK} == y* || ${DO_INSTALL_IMAGEMAGICK} == Y* ]]; then
        echo "Available ImageMagick installation method:"
        echo "  1). Install from Repository (repo)"
        echo "  2). Compile from Source (source)"
        echo "--------------------------------"

        while [[ ${SELECTED_INSTALLER} != "1" && ${SELECTED_INSTALLER} != "2" && ${SELECTED_INSTALLER} != "none" && \
            ${SELECTED_INSTALLER} != "repo" && ${SELECTED_INSTALLER} != "source" ]]; do
            read -rp "Select an option [1-2]: " -e SELECTED_INSTALLER
        done

        case "${SELECTED_INSTALLER}" in
            1 | "repo")
                echo "Installing ImageMagick library from repository..."
                run apt-get install -qq -y imagemagick
            ;;
            2 | "source")
                echo "Installing ImageMagick library from source..."

                local CURRENT_DIR && \
                CURRENT_DIR=$(pwd)

                if [[ "${IMAGEMAGICK_VERSION}" == "latest" ]]; then
                    IMAGEMAGICK_FILENAME="ImageMagick.tar.gz"
                    IMAGEMAGICK_ZIP_URL="https://www.imagemagick.org/download/${IMAGEMAGICK_FILENAME}"
                else
                    IMAGEMAGICK_FILENAME="ImageMagick-${IMAGEMAGICK_VERSION}.tar.gz"
                    IMAGEMAGICK_ZIP_URL="https://download.imagemagick.org/ImageMagick/download/releases/${IMAGEMAGICK_FILENAME}"
                fi

                run cd "${BUILD_DIR}" && \
                run wget "${IMAGEMAGICK_ZIP_URL}" -q --show-progress && \
                run tar -zxf "${IMAGEMAGICK_FILENAME}" && \
                run cd ImageMagick-*/ && \
                run ./configure && \
                run make && \
                run make install && \
                run ldconfig /usr/local/lib && \
                run cd "${CURRENT_DIR}" || return 1
            ;;
            *)
                # Skip installation.
                error "Installer method not supported. ImageMagick installation skipped."
            ;;
        esac

        if [[ "${DRYRUN}" != true ]]; then
            if [[ -n $(command -v magick) ]]; then
                success "ImageMagick version $(magick -version | grep ^Version | cut -d' ' -f3) has been installed."
            elif [[ -n $(command -v convert) ]]; then
                success "ImageMagick version $(convert -version | grep ^Version | cut -d' ' -f3) has been installed."
            fi
        else
            info "ImageMagick installed in dry run mode."
        fi

        # Install PHP Imagick extension.
        #Moved to .env file as custom PHP_EXTENSIONS.
    else
        info "ImageMagick installation skipped."
    fi
}

echo "[ImageMagick Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v magick) || -n $(command -v convert) ]]; then
    info "ImageMagick already exists. Installation skipped..."
else
    init_imagemagick_install "$@"
fi
