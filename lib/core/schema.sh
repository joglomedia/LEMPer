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



# Validate data before exporting it. Legacy runtime keys may be preserved;
# strict mode rejects unknown options and is available through config check.
function validate_config_value() {
    local key="${1}" value="${2}" mode="${3:-compatible}" version
    case "${key}" in
        HOME|PATH|IFS|ENV|CDPATH|GLOBIGNORE|SHELLOPTS|BASHOPTS|BASH_*|LEMPER_CORE_DIR|LEMPER_CORE_SOURCE_DIR|BASE_DIR|SCRIPTS_DIR|CLI_SOURCE_DIR|CLI_SCRIPT_PATH|CLI_PLUGINS_DIR|CONFIG_FILE|ENVFILE|LEMPER_ENV_FILE|LEMPER_CLI_BIN|LEMPER_ROOT|LEMPER_INSTALL_ROOT|LEMPER_ENTRY_CANONICAL|LEMPER_TOOLING_ALREADY_INSTALLED|LEMPER_TOOLS_SKIP_CLI|LEMPER_MAIL_ROOT|LEMPER_MAIL_HOME_ROOT|LD_*)
            printf 'Forbidden configuration key: %s\n' "${key}" >&2; return 1 ;;
        AUTO_INSTALL|FORCE_INSTALL|AUTO_REMOVE|FORCE_REMOVE|DRYRUN|FIX_BROKEN_INSTALL|ENABLE_SWAP|LOGGING|ENCRYPT_CONFIG_AT_REST|SSH_ROOT_LOGIN|SSH_PASSWORDLESS|INSTALL_NGINX|NGINX_WITH_CUSTOMSSL|NGINX_HTTP3|NGINX_WITH_PCRE|NGINX_DYNAMIC_MODULE|NGINX_EXTRA_MODULES|NGX_HTTP_AUTH_PAM|NGX_HTTP_BROTLI|NGX_HTTP_CACHE_PURGE|NGX_HTTP_DAV_EXT|NGX_HTTP_ECHO|NGX_HTTP_FANCYINDEX|NGX_HTTP_GEOIP|NGX_HTTP_GEOIP2|NGX_HTTP_HEADERS_MORE|NGX_HTTP_IMAGE_FILTER|NGX_HTTP_MEMCACHED|NGX_HTTP_NAXSI|NGX_HTTP_NDK|NGX_HTTP_NJS|NGX_HTTP_LUA|NGX_HTTP_PASSENGER|NGX_HTTP_REDIS2|NGX_HTTP_SUBS_FILTER|NGX_HTTP_UPSTREAM_FAIR|NGX_HTTP_VTS|NGX_HTTP_XSLT_FILTER|NGX_MAIL|NGX_NCHAN|NGX_RTMP|NGX_STREAM|NGINX_RATE_LIMITING|NGINX_REWRITE_LOG|DENY_ARCHIVE_FILES|INSTALL_PHP|SESSION_COOKIE_SECURE|INSTALL_PHP_LOADER|INSTALL_PHP_PHALCON|INSTALL_PHP_ZEPHIR|INSTALL_PHP_COMPOSER|INSTALL_IMAGEMAGICK|INSTALL_WEB_ADMIN|INSTALL_MYSQL|MYSQL_SECURE_INSTALL|MYSQL_ALLOW_REMOTE|INSTALL_POSTGRES|INSTALL_MEMCACHED|MEMCACHED_SASL|INSTALL_MONGODB|INSTALL_REDIS|REDIS_REQUIRE_PASSWORD|INSTALL_BUNJS|INSTALL_FTP_SERVER|FTP_SSL_ENABLE|FTP_PASV_MODE|INSTALL_MAILER|INSTALL_SPFDKIM|INSTALL_CERTBOT|ACME_REGISTER_ACCOUNT|ACME_WILDCARD|INSTALL_FW|INSTALL_FAIL2BAN|INSTALL_CROWDSEC|INSTALL_CROWDSEC_WORDPRESS|INSTALL_CROWDSEC_PHPAPPS|INSTALL_MODSEC)
            [[ "${value}" == true || "${value}" == false ]] || return 1 ;;
        SSH_PORT|SERVER_SSH_PORT|FTP_MIN_PORT|FTP_MAX_PORT|POSTGRES_PORT)
            [[ "${value}" =~ ^[0-9]+$ && ${#value} -le 5 && $((10#${value})) -ge 1 && $((10#${value})) -le 65535 ]] || return 1 ;;
        PHP_FPM_MAX_CHILDREN|OPCACHE_MEMORY_MB)
            [[ -z "${value}" || ( "${value}" =~ ^[0-9]+$ && ${#value} -le 7 && $((10#${value})) -gt 0 ) ]] || return 1 ;;
        KEY_HASH_LENGTH|MODSEC_INBOUND_THRESHOLD|MODSEC_OUTBOUND_THRESHOLD|MODSEC_BODY_LIMIT|NGINX_RATE_LIMIT_REQUESTS)
            [[ "${value}" =~ ^[0-9]+$ && ${#value} -le 10 && $((10#${value})) -gt 0 ]] || return 1 ;;
        MODSEC_PARANOIA_LEVEL) [[ "${value}" =~ ^[1-4]$ ]] || return 1 ;;
        ACME_DNS_PROPAGATION_WAIT) [[ "${value}" =~ ^[0-9]+$ && ${#value} -le 4 && $((10#${value})) -le 3600 ]] || return 1 ;;
        ACME_DNS_PROVIDER) [[ "${value}" == cloudflare || "${value}" == digitalocean ]] || return 1 ;;
        REDIS_BACKEND) [[ "${value}" == redis || "${value}" == valkey ]] || return 1 ;;
        NGINX_INSTALLER|REDIS_INSTALLER|MEMCACHED_INSTALLER|FTP_SERVER_INSTALLER|IMAGEMAGICK_INSTALLER|PHP_PHALCON_INSTALLER|CROWDSEC_INSTALLER)
            [[ "${value}" == repo || "${value}" == source ]] || return 1 ;;
        FTP_SERVER_NAME) [[ "${value}" == pureftpd || "${value}" == pure-ftpd || "${value}" == vsftpd ]] || return 1 ;;
        SERVER_PROFILE) [[ "${value}" =~ ^(auto|micro|small|medium|large)$ ]] || return 1 ;;
        MODSEC_ENGINE) [[ "${value}" =~ ^(On|Off|DetectionOnly)$ ]] || return 1 ;;
        FW_CONFIGURATOR) [[ "${value}" =~ ^(ufw|csf|apf)$ ]] || return 1 ;;
        NGINX_ETAG) [[ "${value}" == on || "${value}" == off ]] || return 1 ;;
        LEMPER_USERNAME) is_valid_username "${value}" && [[ "${value}" != root ]] || return 1 ;;
        HOSTNAME) [[ "${value}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ && ${#value} -le 253 ]] || return 1 ;;
        MAILER_HOSTNAME|SENDER_DOMAIN|SERVER_HOSTNAME) [[ -z "${value}" ]] || is_valid_domain "${value}" || return 1 ;;
        MAILER_CERT_PATH) [[ -z "${value}" || ( "${value}" =~ ^/[a-zA-Z0-9_./-]+$ && "${value}" != *..* ) ]] || return 1 ;;
        SERVER_IP) [[ -z "${value}" || "$(core_validate_ipv4 "${value}")" == true ]] || return 1 ;;
        DEFAULT_PHP_VERSION|PHP_VERSIONS)
            [[ -n "${value}" ]] || return 1
            for version in ${value}; do
                [[ "${version}" =~ ^[5-8]\.[0-9]$ ]] || return 1
                if [[ "${mode}" == strict || "${mode}" == install ]]; then
                    [[ "${version}" =~ ^8\.[2-5]$ ]] || return 1
                fi
            done ;;
        PHP_MEMORY_LIMIT) [[ "${value}" =~ ^(-1|[0-9]+[KkMmGg]?)$ ]] || return 1 ;;
        LOG_FILE|BUILD_DIR|ENVIRONMENT|TIMEZONE|LEMPER_PASSWORD|LEMPER_CONFIG_PASSWORD|LEMPER_ADMIN_EMAIL|ADMINER_VERSION|RSA_PUB_KEY|NGINX_REPO_SRC|NGINX_VERSION|NGINX_CUSTOMSSL_VERSION|NGINX_PCRE_VERSION|GEOLITE2_LICENSE_KEY|LUA_JIT_VERSION|LUA_RESTY_CORE_VERSION|LUA_RESTY_LRUCACHE_VERSION|LUA_NGINX_MODULE_VERSION|LUA_NGINX_STREAM_MODULE_VERSION|PHP_EXTENSIONS|PHP_LOADER|PHP_PHALCON_VERSION|PHP_ZEPHIR_VERSION|IMAGEMAGICK_VERSION|MYSQL_SERVER|MYSQL_VERSION|MYSQL_REPO_MIRROR_URL|MYSQL_ROOT_PASSWORD|MARIABACKUP_USER|MARIABACKUP_PASS|POSTGRES_VERSION|POSTGRES_PGDATA|POSTGRES_SUPERUSER|POSTGRES_DB_USER|POSTGRES_DB_PASS|MEMCACHED_VERSION|MEMCACHED_USERNAME|MEMCACHED_PASSWORD|MONGODB_VERSION|MONGODB_ADMIN_USER|MONGODB_ADMIN_PASSWORD|REDIS_VERSION|REDIS_PASSWORD|BUNJS_VERSION|FTP_SERVER_VERSION|HOSTNAME_CERT_PATH|DH_PARAM_GROUP|DEFAULT_PYTHON_VERSION|ACME_DNS_API_TOKEN|FAIL2BAN_INSTALLER|FAIL2BAN_VERSION|CROWDSEC_VERSION|MARIABACKUP_USERNAME|MARIABACKUP_PASSWORD|PSQL_DB_USER|PSQL_DB_PASS|PSQL_DB_TEST|MONGODB_ADMIN_PASS|MONGODB_HOST|MONGODB_PORT|MEMCACHED_INSTANCE|LEMPER_CONFIG_VERSION)
            return 0 ;;
        *)
            [[ "${mode}" == compatible ]] || { printf 'Unknown configuration key: %s\n' "${key}" >&2; return 1; } ;;
    esac
    return 0
}

function validate_config_file() {
    local file="${1}" mode="${2:-compatible}" line key value number=0
    [[ -r "${file}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        number=$((number+1))
        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z "${line}" || "${line}" == \#* || "${line}" == \[* ]] && continue
        [[ "${line}" == *=* ]] || { printf 'Malformed configuration at line %s\n' "${number}" >&2; return 1; }
        key="${line%%=*}"; key="${key%"${key##*[![:space:]]}"}"
        [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
        value="${line#*=}"; value="${value#\"}"; value="${value%\"}"; value="${value#\'}"; value="${value%\'}"
        if ! validate_config_value "${key}" "${value}" "${mode}"; then
            printf 'Invalid configuration for %s at line %s (value redacted).\n' "${key}" "${number}" >&2
            return 1
        fi
    done < "${file}"
    # Cross-option constraints use values from the actual file, not the caller's env.
    local minimum="" maximum="" parser_key parser_value key_only=false unattended=true public_key="" wildcard=false dns_token=""
    while IFS=$'\t' read -r parser_key parser_value; do
        case "${parser_key}" in FTP_MIN_PORT) minimum="${parser_value}" ;; FTP_MAX_PORT) maximum="${parser_value}" ;; SSH_PASSWORDLESS) key_only="${parser_value}" ;; AUTO_INSTALL) unattended="${parser_value}" ;; RSA_PUB_KEY) public_key="${parser_value}" ;; ACME_WILDCARD) wildcard="${parser_value}" ;; ACME_DNS_API_TOKEN) dns_token="${parser_value}" ;; esac
    done < <(safe_parse_dotenv "${file}")
    if [[ "${mode}" == install && "${key_only}" == true && "${unattended}" == true ]]; then
        valid_ssh_key_material "${public_key}" || {
            printf 'Unattended key-only SSH requires a valid RSA_PUB_KEY before installation.\n' >&2
            return 1
        }
    fi
    if [[ "${mode}" == install && "${wildcard}" == true && -z "${dns_token}" ]]; then
        printf 'Wildcard DNS-01 installation requires ACME_DNS_API_TOKEN.\n' >&2
        return 1
    fi
    if [[ -n "${minimum}" && -n "${maximum}" ]] && ((10#${minimum} > 10#${maximum})); then
        printf 'FTP_MIN_PORT must not exceed FTP_MAX_PORT.\n' >&2
        return 1
    fi
}
