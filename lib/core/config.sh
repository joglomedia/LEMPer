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


# Remove exactly one matching outer quote pair; inner/one-sided quotes are data.
function core_unquote_dotenv_value() {
    local -n dotenv_value="$1"
    if [[ ${#dotenv_value} -ge 2 && ( "$dotenv_value" == \"*\" || "$dotenv_value" == \'*\' ) ]]; then
        dotenv_value="${dotenv_value:1:${#dotenv_value}-2}"
    fi
}

function core_safe_parse_dotenv() {
    local envfile="${1}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        # Normalize CRLF files edited on Windows.
        line="${line%$'\r'}"
        # Skip comments and section headers.
        line="${line#"${line%%[![:space:]]*}"}"  # ltrim
        [[ -z "${line}" || "${line}" == \#* || "${line}" == \[* ]] && continue
        # Skip lines without a key=value separator.
        [[ "${line}" != *=* ]] && continue
        # Split on first =. Values keep spaces (SSH public keys, paths, ...).
        local key="${line%%=*}"
        local value="${line#*=}"
        key="${key%"${key##*[![:space:]]}"}"  # rtrim
        core_unquote_dotenv_value value
        # Validate key name (prevent injection).
        if [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            printf '%s\t%s\n' "${key}" "${value}"
        fi
    done < "${envfile}"
}

function core_set_env_value() {
    local file="${1}"
    local key="${2}"
    local value="${3}"

    [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
    [[ -f "${file}" ]] || return 1

    if [[ "${DRYRUN:-false}" == true ]]; then
        echo_color "${YELLOW}" -n "would set "
        echo "${key} in ${file}"
        return 0
    fi

    # Only add an outer wrapper when a future read would otherwise consume
    # actual quote characters. Normal values keep their established spelling.
    local normalized="$value"
    core_unquote_dotenv_value normalized
    [[ "$normalized" == "$value" ]] || value="'$value'"
    local tmp
    tmp=$(mktemp "${file}.XXXXXX") || return 1

    # ENVIRON avoids awk -v escape processing in the value.
    if LEMPER_ENV_VALUE="${value}" awk -v k="${key}" '
        BEGIN { v = ENVIRON["LEMPER_ENV_VALUE"]; found = 0 }
        index($0, k "=") == 1 { if (!found) { print k "=" v; found = 1 }; next }
        { print }
        END { if (!found) print k "=" v }
    ' "${file}" > "${tmp}"; then
        # Rewrite in place to keep ownership and mode.
        if ! cat "${tmp}" > "${file}"; then
            rm -f "${tmp}"
            return 1
        fi
        rm -f "${tmp}"
        return 0
    fi

    rm -f "${tmp}"
    return 1
}

function core_is_ssh_public_key() {
    local key="${1:-}"
    key="${key%$'\r'}"
    key="${key#"${key%%[![:space:]]*}"}"  # ltrim
    key="${key%"${key##*[![:space:]]}"}"  # rtrim

    [[ "${key}" =~ ^(ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)[[:space:]]+[A-Za-z0-9+/]+={0,3}([[:space:]].*)?$ ]]
}

function core_init_config() {
    [[ "${DRYRUN:-false}" != true ]] || { info "Would initialize installed configuration."; return 0; }
    install -d -m 0700 /etc/lemper /etc/lemper/vhost.d || return 1
    if [[ "${ENCRYPT_CONFIG_AT_REST:-false}" == true && ! -f /etc/lemper/.config_key ]]; then
        local config_key temporary
        temporary=$(mktemp /etc/lemper/.config_key.XXXXXXXX) || return 1
        config_key=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9')
        if ! printf '%s\n' "$config_key" > "$temporary" ||
           ! chmod 0600 "$temporary" || ! mv -f "$temporary" /etc/lemper/.config_key; then
            rm -f "$temporary"; return 1
        fi
        success "Encrypted config key generated at /etc/lemper/.config_key"
    fi
    if [[ ! -f /etc/lemper/lemper.conf ]]; then
        local seed
        seed=$(mktemp /etc/lemper/.config.XXXXXXXX) || return 1
        if [[ -n "${ENVFILE:-}" && -r "$ENVFILE" ]]; then
            validate_config_file "$ENVFILE" compatible || { rm -f "$seed"; return 1; }
            if [[ "${ENCRYPT_CONFIG_AT_REST:-false}" == true ]]; then
                openssl enc -aes-256-cbc -a -salt -md sha256 -pbkdf2 \
                    -pass file:/etc/lemper/.config_key -in "$ENVFILE" -out "$seed" ||
                    { rm -f "$seed"; return 1; }
            else
                cat "$ENVFILE" > "$seed" || { rm -f "$seed"; return 1; }
            fi
        fi
        if ! chmod 0600 "$seed" || ! mv -f "$seed" /etc/lemper/lemper.conf; then
            rm -f "$seed"; return 1
        fi
    fi
    save_log -e "# LEMPer configuration.\n# Edit here if you change your password manually, but do NOT delete!"
}

# Explicit full-stack installation reconciles its validated effective profile.
# Existing generated secrets were merged by the entry adapter; keep a protected backup.
function core_store_install_profile() {
    local profile="$1" file="/etc/lemper/lemper.conf" temporary backup password
    validate_config_file "$profile" install || return 1
    [[ "${DRYRUN:-false}" != true ]] || return 0
    local existing=false
    [[ ! -f "$file" ]] || existing=true
    core_init_config || return 1
    temporary=$(mktemp /etc/lemper/.install-profile.XXXXXXXX) || return 1
    if [[ "${ENCRYPT_CONFIG_AT_REST:-false}" == true ]]; then
        password=$(resolve_config_password) || { rm -f "$temporary"; return 1; }
        if ! openssl enc -aes-256-cbc -a -salt -md sha256 -pbkdf2 \
            -pass fd:3 3<<<"$password" -in "$profile" -out "$temporary"; then
            rm -f "$temporary"; return 1
        fi
    else
        cat "$profile" > "$temporary" || { rm -f "$temporary"; return 1; }
    fi
    if [[ "$existing" == true ]]; then
        backup=$(mktemp /etc/lemper/.pre-install-profile.XXXXXXXX) || { rm -f "$temporary"; return 1; }
        cp "$file" "$backup" || { rm -f "$temporary" "$backup"; return 1; }
        chmod 0600 "$backup" || { rm -f "$temporary"; return 1; }
    fi
    if ! chmod 0600 "$temporary" || ! mv -f "$temporary" "$file"; then
        rm -f "$temporary"
        return 1
    fi
}

function core_save_config() {
    if [[ ${DRYRUN} != true ]]; then
        local config_file="/etc/lemper/lemper.conf"

        if [[ "${ENCRYPT_CONFIG_AT_REST}" == true ]]; then
            # Decrypt, write, re-encrypt.
            local temp_dec pw
            temp_dec=$(mktemp /tmp/lemper_save.XXXXXX)
            pw=$(resolve_config_password) 2>/dev/null || pw="${LEMPER_PASSWORD}"

            if is_config_encrypted "${config_file}"; then
                local decrypted=false

                if openssl enc -aes-256-cbc -d -a -salt -md sha256 -pbkdf2 \
                    -pass fd:3 3<<<"${pw}" -in "${config_file}" -out "${temp_dec}" 2>/dev/null; then
                    decrypted=true
                # Fall back to the admin password for configs written before
                # the install-time key file became authoritative.
                elif [[ -n "${LEMPER_PASSWORD}" && "${LEMPER_PASSWORD}" != "${pw}" ]] && \
                    openssl enc -aes-256-cbc -d -a -salt -md sha256 -pbkdf2 \
                        -pass fd:3 3<<<"${LEMPER_PASSWORD}" -in "${config_file}" -out "${temp_dec}" 2>/dev/null; then
                    decrypted=true
                fi

                if [[ "${decrypted}" != true ]]; then
                    secure_shred "${temp_dec}"
                    error "Failed to decrypt ${config_file}; refusing to overwrite it."
                    return 1
                fi
            elif [[ -f "${config_file}" ]]; then
                cp "${config_file}" "${temp_dec}"
            fi

            echo "$@" >> "${temp_dec}"

            # Re-encrypt with the preferred password, migrating legacy
            # password-encrypted configs to the key file.
            if [[ -n "${pw}" ]]; then
                openssl enc -aes-256-cbc -a -salt -md sha256 -pbkdf2 \
                    -pass fd:3 3<<<"${pw}" -in "${temp_dec}" -out "${config_file}"
            else
                cp "${temp_dec}" "${config_file}"
            fi
            secure_shred "${temp_dec}"
        else
            [ -f "${config_file}" ] && echo "$@" >> "${config_file}"
        fi
    fi
}

function core_secure_config() {
    if [[ ${DRYRUN} != true ]]; then
        local config_file="/etc/lemper/lemper.conf"
        if [ -f "${config_file}" ] && [[ "${ENCRYPT_CONFIG_AT_REST}" == true ]]; then
            local pw
            pw=$(resolve_config_password) 2>/dev/null || pw="${LEMPER_PASSWORD}"
            if [[ -n "${pw}" ]]; then
                run openssl enc -aes-256-cbc -a -salt -md sha256 -pbkdf2 -pass fd:3 3<<<"${pw}" \
                    -in "${config_file}" -out "${config_file}.enc"
                secure_shred "${config_file}"
                mv "${config_file}.enc" "${config_file}"
            fi
        fi
    fi
}

function core_is_config_encrypted() {
    local file="${1:-/etc/lemper/lemper.conf}"
    [[ -f "${file}" ]] && head -c 10 "${file}" | grep -qE '^(U2FsdGVkX1|Salted__)'
}

function core_secure_shred() {
    local file="${1}"
    [[ -f "${file}" ]] || return 0
    if command -v shred &>/dev/null; then
        shred -u -z -n 3 "${file}" 2>/dev/null || rm -f "${file}"
    else
        rm -f "${file}"
    fi
}

function core_resolve_config_password() {
    if [[ -n "${LEMPER_CONFIG_PASSWORD}" ]]; then
        printf '%s' "${LEMPER_CONFIG_PASSWORD}"
        return 0
    fi

    if [[ -f /etc/lemper/.config_key ]]; then
        cat /etc/lemper/.config_key
        return 0
    fi

    # Legacy fallback for installs predating the key file.
    if [[ -n "${LEMPER_PASSWORD}" ]]; then
        printf '%s' "${LEMPER_PASSWORD}"
        return 0
    fi

    return 1
}

function safe_parse_dotenv() {
    core_safe_parse_dotenv "$@"
}

function set_env_value() {
    core_set_env_value "$@"
}

function is_ssh_public_key() {
    core_is_ssh_public_key "$@"
}

function init_config() {
    core_init_config "$@"
}

function save_config() {
    core_save_config "$@"
}

function secure_config() {
    core_secure_config "$@"
}

function is_config_encrypted() {
    core_is_config_encrypted "$@"
}

function secure_shred() {
    core_secure_shred "$@"
}

function resolve_config_password() {
    core_resolve_config_password
}
