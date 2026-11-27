#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Shared Security Helpers                                          |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2026 MasEDI.Net (https://masedi.net/lemper)          |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@lemper.cloud so we can send you a copy immediately.          |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <me@masedi.net>                                |
# +-------------------------------------------------------------------------+

##
# Build OpenSSL or QuicTLS from source
# Sets NGX_CONFIGURE_ARGS with SSL paths
##
function build_openssl() {
    local version="${1:-${NGINX_CUSTOMSSL_VERSION:-openssl-3.5.9}}" source checksum="" archive expected directory
    [[ "$version" =~ ^openssl-[0-9]+\.[0-9]+\.[0-9]+(-quic[0-9]+)?$ ]] || {
        error "Invalid OpenSSL source version."
        return 1
    }
    [[ "${NGINX_BUILD_DIR:-}" == /* && "$NGINX_BUILD_DIR" != *$'\n'* && "$NGINX_BUILD_DIR" != *$'\r'* && ! -L "$NGINX_BUILD_DIR" ]] || return 1
    directory="$NGINX_BUILD_DIR/$version"
    archive="$NGINX_BUILD_DIR/$version.tar.gz"
    if grep -iq quic <<<"$version"; then
        # Explicit legacy QuicTLS pins retain their existing trusted source.
        source="https://github.com/quictls/openssl/archive/refs/tags/$version.tar.gz"
    else
        source="https://github.com/openssl/openssl/releases/download/$version/$version.tar.gz"
        checksum="$source.sha256"
    fi
    if [[ "${DRYRUN:-false}" == true ]]; then
        info "Would prepare verified OpenSSL sources for the Nginx build."
    else
        lemper_exec mkdir -p -m 0700 -- "$NGINX_BUILD_DIR" || return 1
        lemper_exec curl -fsSL --proto '=https' --retry 3 -o "$archive" "$source" || return 1
        if [[ -n "$checksum" ]]; then
            expected=$(curl -fsSL --proto '=https' --retry 3 "$checksum") || return 1
            expected="${expected%%[[:space:]]*}"
            [[ "$expected" =~ ^[a-fA-F0-9]{64}$ && "$(sha256sum "$archive" | cut -d ' ' -f1)" == "${expected,,}" ]] || {
                error "OpenSSL archive checksum mismatch."
                return 1
            }
        fi
        [[ ! -L "$directory" ]] || return 1
        lemper_exec install -d "$directory" || return 1
        lemper_exec tar --extract --gzip --file "$archive" --directory "$directory" --strip-components=1 || return 1
    fi
    # Nginx's build system builds/links these sources, avoiding library-path and
    # release-archive directory assumptions in the old standalone build.
    NGX_CONFIGURE_ARGS+=("--with-openssl=$directory" "--with-openssl-opt=no-shared no-tests")
    if [[ "${NGINX_HTTP3:-false}" == true ]]; then NGX_CONFIGURE_ARGS+=("--with-http_v3_module"); fi
}

##
# Build LibreSSL from source
# Sets NGX_CONFIGURE_ARGS with SSL paths
##
function build_libressl() {
    local SSL_VERSION="${1:-${NGINX_CUSTOMSSL_VERSION}}"

    [[ "$SSL_VERSION" =~ ^libressl-[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    echo "Building LibreSSL ${SSL_VERSION}..."

    local LIBRESSL_SOURCE_URL="https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/${SSL_VERSION}.tar.gz"

    if curl -sLI "${LIBRESSL_SOURCE_URL}" | grep -q "HTTP/[.12]* [2].."; then
        run curl -sSL -o "${SSL_VERSION}.tar.gz" "${LIBRESSL_SOURCE_URL}" \
            && run tar -zxf "${SSL_VERSION}.tar.gz"

        if [[ -d "${NGINX_BUILD_DIR}/${SSL_VERSION}" ]]; then
            NGX_CONFIGURE_ARGS+=(
                "--with-openssl=${NGINX_BUILD_DIR}/${SSL_VERSION}"
                "--with-openssl-opt=no-weak-ssl-ciphers"
                "--with-http_v3_module"
            )
            return 0
        fi
    else
        error "Unable to determine the LibreSSL source page."
        return 1
    fi
}

##
# Build BoringSSL from source
# Requires Golang to be installed
# Sets NGX_CONFIGURE_ARGS with SSL paths
##
function build_boringssl() {
    local SSL_VERSION="${1:-${NGINX_CUSTOMSSL_VERSION}}"
    local NB_PROC
    NB_PROC=$(get_cpu_cores)

    core_is_valid_custom_ssl_version "$SSL_VERSION" || return 1
    [[ "$SSL_VERSION" == boringssl-* ]] || return 1
    echo "Building BoringSSL ${SSL_VERSION}..."

    # BoringSSL requires Golang
    install_golang_if_missing

    # Parse version
    local SAVEIFS=${IFS}
    IFS='- ' read -r -a BSPARTS <<<"${SSL_VERSION}"
    IFS=${SAVEIFS}
    local BORINGSSL_VERSION=${BSPARTS[1]}
    [[ -z ${BORINGSSL_VERSION} || ${BORINGSSL_VERSION} == "latest" ]] && BORINGSSL_VERSION="master"

    local BORINGSSL_SOURCE_URL="https://boringssl.googlesource.com/boringssl/+archive/refs/heads/${BORINGSSL_VERSION}.tar.gz"

    if curl -sLI "${BORINGSSL_SOURCE_URL}" | grep -q "HTTP/[.12]* [2].."; then
        run curl -sSL -o "${SSL_VERSION}.tar.gz" "${BORINGSSL_SOURCE_URL}" \
            && run mkdir -p "${SSL_VERSION}" \
            && run tar -zxf "${SSL_VERSION}.tar.gz" -C "${SSL_VERSION}" \
            && run cd "${NGINX_BUILD_DIR}/${SSL_VERSION}" \
            &&
            # Make an .openssl directory for nginx and symlink BoringSSL's include directory
            run mkdir -p build .openssl/lib .openssl/include \
            && run ln -sf "${NGINX_BUILD_DIR}/${SSL_VERSION}/include/openssl" .openssl/include/openssl \
            &&
            # Fix "Error 127" during build
            run touch "${NGINX_BUILD_DIR}/${SSL_VERSION}/.openssl/include/openssl/ssl.h" \
            &&
            # Build BoringSSL static
            run cmake -B"${NGINX_BUILD_DIR}/${SSL_VERSION}/build" -H"${NGINX_BUILD_DIR}/${SSL_VERSION}" \
            && run make -C"${NGINX_BUILD_DIR}/${SSL_VERSION}/build" -j"${NB_PROC}" \
            &&
            # Copy the BoringSSL crypto libraries
            run cp build/crypto/libcrypto.a build/ssl/libssl.a .openssl/lib \
            && run cd "${NGINX_EXTRA_MODULE_DIR}" || return 1

        NGX_CONFIGURE_ARGS+=(
            "--with-cc-opt=\"-I${NGINX_BUILD_DIR}/${SSL_VERSION}/.openssl/include\""
            "--with-ld-opt=\"-L${NGINX_BUILD_DIR}/${SSL_VERSION}/.openssl/lib\""
            "--with-http_v3_module"
        )
        return 0
    else
        error "Unable to determine the BoringSSL source page."
        return 1
    fi
}

##
# Install Golang if not present (required for BoringSSL)
##
function install_golang_if_missing() {
    if [[ -n $(command -v go) ]]; then
        echo "Golang already installed."
        return 0
    fi

    echo "Installing Golang (required for BoringSSL)..."

    local GOLANG_VER="1.17.8"
    local DISTRIB_ARCH
    DISTRIB_ARCH=$(get_distrib_arch)

    case "${DISTRIB_NAME}" in
        debian)
            local GOLANG_DOWNLOAD_URL="https://go.dev/dl/go${GOLANG_VER}.linux-${DISTRIB_ARCH}.tar.gz"

            if curl -sLI "${GOLANG_DOWNLOAD_URL}" | grep -q "HTTP/[.12]* [2].."; then
                run curl -sSL -o golang.tar.gz "${GOLANG_DOWNLOAD_URL}" \
                    && run tar -C /usr/local -zxf golang.tar.gz \
                    && run bash -c "echo -e '\nexport PATH=\"\$PATH:/usr/local/go/bin\"' >> ~/.profile"
                # shellcheck disable=SC1090
                . ~/.profile
            else
                warning "Unable to determine Golang source page."
            fi
            ;;
        ubuntu)
            lemper_load_module services/apt/catalog \
                && lemper_apt_prepare_repository golang \
                && run apt-get update -q -y \
                && run apt-get install -q -y golang-go
            ;;
        *)
            fail "Unsupported distribution for Golang installation."
            ;;
    esac
}

##
# Build PCRE JIT from source
# Sets NGX_CONFIGURE_ARGS with PCRE paths
##
function build_pcre() {
    local PCRE_VERSION="${1:-${NGINX_PCRE_VERSION:-8.45}}"

    echo "Building PCRE JIT ${PCRE_VERSION}..."

    local PCRE_SOURCE_URL="https://onboardcloud.dl.sourceforge.net/project/pcre/pcre/${PCRE_VERSION}/pcre-${PCRE_VERSION}.tar.gz"

    if curl -sLI "${PCRE_SOURCE_URL}" | grep -q "HTTP/[.12]* [2].."; then
        run curl -sSL -o "pcre-${PCRE_VERSION}.tar.gz" "${PCRE_SOURCE_URL}" \
            && run tar -zxf "pcre-${PCRE_VERSION}.tar.gz"

        if [[ -d "${NGINX_BUILD_DIR}/pcre-${PCRE_VERSION}" ]]; then
            NGX_CONFIGURE_ARGS+=(
                "--with-pcre=${NGINX_BUILD_DIR}/pcre-${PCRE_VERSION}"
                "--with-pcre-jit"
            )
            return 0
        fi
    else
        error "Unable to determine PCRE JIT ${PCRE_VERSION} source."
        return 1
    fi
}

##
# Build custom SSL based on configuration
##
function build_custom_ssl() {
    local SSL_VERSION="${NGINX_CUSTOMSSL_VERSION:-openssl-3.5.9}"

    core_is_valid_custom_ssl_version "$SSL_VERSION" || {
        error "Invalid custom TLS source version."
        return 1
    }
    echo "Building custom SSL ${SSL_VERSION^}..."

    run cd "${NGINX_BUILD_DIR}" || return 1

    if grep -iq openssl <<<"${SSL_VERSION}"; then
        build_openssl "${SSL_VERSION}"
    elif grep -iq libressl <<<"${SSL_VERSION}"; then
        build_libressl "${SSL_VERSION}"
    elif grep -iq boringssl <<<"${SSL_VERSION}"; then
        build_boringssl "${SSL_VERSION}"
    else
        error "Unable to determine the CustomSSL version."
        echo "Falling back to the default system's OpenSSL..."
        return 1
    fi
}
