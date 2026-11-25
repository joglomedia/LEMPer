#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Protected Configuration Updates                                  |
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

# Prepare a protected replacement without changing the installed profile.
# Preserve encryption, credentials, and unrelated settings; no values are logged.
# An empty result means the setting already has the requested value.
function core_config_prepare_value() {
    local file="$1" key="$2" value="$3" plain prepared password="" current="" parsed_key parsed_value count=0 encrypted=false
    [[ -f "$file" && ! -L "$file" ]] || { error "A regular installed profile is required."; return 1; }
    [[ "${DRYRUN:-false}" != true ]] || { info "Would update $key in the installed profile."; return 0; }
    plain=$(mktemp "${file}.plain.XXXXXXXX") || return 1
    if is_config_encrypted "$file"; then
        encrypted=true
        password=$(resolve_config_password) || { secure_shred "$plain"; return 1; }
        if ! openssl enc -aes-256-cbc -d -a -salt -md sha256 -pbkdf2 -pass fd:3 3<<<"$password" \
            -in "$file" -out "$plain" 2>/dev/null; then
            if ! openssl enc -aes-256-cbc -d -a -salt -md sha256 -pass fd:3 3<<<"$password" \
                -in "$file" -out "$plain" 2>/dev/null; then
                secure_shred "$plain"; error "Cannot decrypt the installed profile."; return 1
            fi
        fi
    else
        cp "$file" "$plain" || { secure_shred "$plain"; return 1; }
        chmod 0600 "$plain" || { secure_shred "$plain"; return 1; }
    fi
    while IFS=$'\t' read -r parsed_key parsed_value; do
        if [[ "$parsed_key" == "$key" ]]; then current="$parsed_value"; count=$((count+1)); fi
    done < <(safe_parse_dotenv "$plain")
    if [[ "$count" == 1 && "$current" == "$value" ]]; then secure_shred "$plain"; return 0; fi
    if ! set_env_value "$plain" "$key" "$value" || ! validate_config_file "$plain"; then
        secure_shred "$plain"; return 1
    fi
    prepared=$(mktemp "${file}.prepared.XXXXXXXX") || { secure_shred "$plain"; return 1; }
    local rc=0
    if [[ "$encrypted" == true ]]; then
        openssl enc -aes-256-cbc -a -salt -md sha256 -pbkdf2 -pass fd:3 3<<<"$password" \
            -in "$plain" -out "$prepared" || rc=1
    else cp "$plain" "$prepared" || rc=1; fi
    secure_shred "$plain"
    if [[ "$rc" != 0 ]] || ! chown --reference="$file" "$prepared" || ! chmod 0600 "$prepared"; then
        secure_shred "$prepared"; return 1
    fi
    printf '%s\n' "$prepared"
}
