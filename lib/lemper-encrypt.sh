#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Encrypted Configuration (at-rest encryption)               |
# +-------------------------------------------------------------------------+
# | Provides AES-256-CBC encryption/decryption for /etc/lemper/lemper.conf. |
# | Backward compatible: plaintext configuration files load as-is.          |
# |                                                                         |
# | Invoked as: library - sourced by LEMPer scripts.                        |
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
# Check if a config file is encrypted (starts with Salted__ header from openssl).
##
function is_config_encrypted() {
    local file="${1}"

    if [[ ! -f "${file}" ]]; then
        return 1
    fi

    # OpenSSL `enc` supports CBC; AEAD ciphers such as GCM are rejected.
    if head -c 10 "${file}" | grep -qE '^(U2FsdGVkX1|Salted__)'; then
        return 0
    fi

    return 1
}

##
# Securely delete a file (overwrite + remove).
# Falls back to regular rm if shred is unavailable.
##
function secure_shred() {
    local file="${1}"

    if [[ ! -f "${file}" ]]; then
        return 0
    fi

    if command -v shred &>/dev/null; then
        shred -u -z -n 3 "${file}" 2>/dev/null || rm -f "${file}"
    elif command -v srm &>/dev/null; then
        srm -f "${file}" 2>/dev/null || rm -f "${file}"
    else
        rm -f "${file}"
    fi
}

##
# Resolve the config password from available sources:
#   1. --password CLI flag (already parsed into LEMER_CONFIG_PASSWORD)
#   2. LEMPER_CONFIG_PASSWORD environment variable
#   3. /etc/lemper/.config_key file (auto-generated at install time)
##
function resolve_config_password() {
    # 1. CLI flag (set by the dispatcher before loading plugins).
    if [[ -n "${LEMPER_CONFIG_PASSWORD}" ]]; then
        printf '%s' "${LEMPER_CONFIG_PASSWORD}"
        return 0
    fi

    # 2. Environment variable fallback.
    if [[ -n "${LEMPER_CONFIG_PASSWORD_ENV:-${LEMPER_CONFIG_PASSWORD}}" ]]; then
        printf '%s' "${LEMPER_CONFIG_PASSWORD_ENV:-${LEMPER_CONFIG_PASSWORD}}"
        return 0
    fi

    # 3. Stored key file (generated at install time, mode 0600, root-only).
    local key_file="/etc/lemper/.config_key"
    if [[ -f "${key_file}" ]]; then
        cat "${key_file}"
        return 0
    fi

    return 1
}

##
# Decrypt an encrypted config file to a temporary plaintext file.
# Arguments: encrypted_file [output_file]
# Returns: path to decrypted temp file (via stdout), or empty on failure.
##
function decrypt_config() {
    local encrypted_file="${1}"
    local output_file="${2:-}"
    local password

    # Resolve password.
    password=$(resolve_config_password)
    if [[ -z "${password}" ]]; then
        # Prompt interactively if no password source found.
        if [[ -t 0 ]]; then
            local input
            read -rs -p "Enter config decryption password: " input
            echo ""
            password="${input}"
        else
            fail "Cannot decrypt config: no password provided. Set LEMPER_CONFIG_PASSWORD env var or use --password."
        fi
    fi

    if [[ -z "${output_file}" ]]; then
        output_file=$(mktemp /tmp/lemper_config.XXXXXX)
    fi

    # Decrypt using AES-256-CBC (GCM was never supported by `openssl enc`).
    if ! openssl enc -aes-256-cbc -d -a -salt -md sha256 -pbkdf2 \
        -k "${password}" -in "${encrypted_file}" -out "${output_file}" 2>/dev/null; then
        if ! openssl enc -aes-256-cbc -d -a -salt -md sha256 \
            -k "${password}" -in "${encrypted_file}" -out "${output_file}" 2>/dev/null; then
            secure_shred "${output_file}"
            fail "Failed to decrypt config: incorrect password or corrupted file."
        fi
    fi

    echo "${output_file}"
}

##
# Encrypt a plaintext config file in-place to an encrypted format.
# The original plaintext file is securely shredded after encryption.
# Arguments: plaintext_file password
##
function encrypt_config() {
    local plaintext_file="${1}"
    local password="${2}"
    local encrypted_file="${plaintext_file}.enc"

    if [[ -z "${password}" ]]; then
        password=$(resolve_config_password)
        if [[ -z "${password}" ]]; then
            fail "Cannot encrypt config: no password provided."
        fi
    fi

    # Encrypt using AES-256-CBC.
    if openssl enc -aes-256-cbc -a -salt -md sha256 -pbkdf2 \
        -k "${password}" -in "${plaintext_file}" -out "${encrypted_file}"; then
        # Zero out the plaintext file before removing.
        secure_shred "${plaintext_file}"
        # Move encrypted file to replace original.
        mv "${encrypted_file}" "${plaintext_file}"
        success "Config encrypted at rest: ${plaintext_file}"
    else
        fail "Failed to encrypt config file."
    fi
}

##
# Load configuration from file, handling both plaintext and encrypted formats.
# Uses safe_parse_dotenv() — no eval-based sourcing (SEC-06 mitigation).
# Arguments: config_file
##
function load_config() {
    local config_file="${1}"

    if [[ ! -f "${config_file}" ]]; then
        echo "LEMPer Stack configuration required, but the file doesn't exist."
        echo "It should be created during installation process and placed under '/etc/lemper/lemper.conf'."
        exit 1
    fi

    local source_file="${config_file}"
    local temp_decrypted=""

    # Check if config is encrypted.
    if is_config_encrypted "${config_file}"; then
        # The header is authoritative: the flag is not inherited under sudo.
        temp_decrypted=$(decrypt_config "${config_file}")
        if [[ -z "${temp_decrypted}" ]]; then
            fail "Failed to decrypt configuration."
        fi
        source_file="${temp_decrypted}"
    fi

    # Load the configuration using safe parser (no eval).
    # This replaces the original eval-based loader (SEC-06 mitigation).
    # Clean environment first — unset existing vars from config file.
    while IFS=$'\t' read -r key _; do
        unset "${key}" 2>/dev/null || true
    done < <(safe_parse_dotenv "${source_file}")

    # Safely load key=value pairs without eval.
    while IFS=$'\t' read -r key value; do
        export "${key}=${value}"
    done < <(safe_parse_dotenv "${source_file}")

    # Securely clean up temp file if we decrypted one.
    if [[ -n "${temp_decrypted}" ]]; then
        secure_shred "${temp_decrypted}"
    fi
}

##
# Save a configuration key-value pair to the config file.
# If config is encrypted, write to a temp file, then re-encrypt.
# Arguments: key value [config_file]
##
function save_config_encrypted() {
    local key="${1}"
    local value="${2}"
    local config_file="${3:-/etc/lemper/lemper.conf}"

    if [[ -n "${DRYRUN}" && "${DRYRUN}" == true ]]; then
        echo "would save: ${key}=${value} → ${config_file}"
        return 0
    fi

    local working_file="${config_file}"
    local temp_decrypted=""

    # If config is encrypted, decrypt first.
    if is_config_encrypted "${config_file}"; then
        temp_decrypted=$(decrypt_config "${config_file}")
        working_file="${temp_decrypted}"
    fi

    # Append the key-value pair.
    echo "${key}=${value}" >> "${working_file}"

    # If we decrypted, re-encrypt the working copy.
    if [[ -n "${temp_decrypted}" && -f "${working_file}" ]]; then
        local password
        password=$(resolve_config_password)
        openssl enc -aes-256-cbc -a -salt -md sha256 -pbkdf2 \
            -k "${password}" -in "${working_file}" -out "${config_file}"
        secure_shred "${working_file}"
    fi
}

##
# Check if the TUI requires a password (config is encrypted).
##
function config_needs_password() {
    local config_file="${1:-/etc/lemper/lemper.conf}"
    is_config_encrypted "${config_file}"
}

# Library module: safe to source. Direct execution and CLI dispatch only
# print a notice; configuration encryption is handled by lemper-cli itself.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "lemper-encrypt is a library module; source it from a LEMPer script."
    exit 0
elif [[ "$(type -t requires_root)" == "function" && -z "${LEMPER_ENCRYPT_LIB_ONLY:-}" ]]; then
    echo "lemper-encrypt is a library module; there is no 'lemper-cli encrypt' command."
    echo "Configuration encryption is handled automatically by lemper-cli."
fi
