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

# Functions only; the installer/runtime caller owns the shared operation lock.
function lemper_mariabackup_secret_valid() {
    [[ ${#1} -le 1024 && ! "$1" =~ [[:cntrl:]] ]]
}
function lemper_mariabackup_quote_option() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}
# Root credentials must survive a later installer failure after ALTER USER.
function lemper_mariadb_store_root_credential() (
    local profile="${LEMPER_MARIADB_PROFILE:-/etc/lemper/lemper.conf}" prepared="" backup
    [[ -n "${MYSQL_ROOT_PASSWORD:-}" ]] && lemper_mariabackup_secret_valid "$MYSQL_ROOT_PASSWORD" || return 1
    lemper_load_module services/mariadb/database || return 1
    lemper_load_module core/config-update || return 1
    if [[ "${DRYRUN:-false}" == true ]]; then
        info "Would protect MariaDB root credentials."
        return 0
    fi
    if ! lemper_db_directory_safe "${profile%/*}" || [[ ! -f "$profile" || -L "$profile" ]] \
        || [[ "$(stat -c %u "$profile")" != "$EUID" ]]; then
        error "A trusted installed profile is required for root credentials."
        return 1
    fi
    (((8#$(stat -c %a "$profile") & 0022) == 0)) || return 1
    lemper_exec chmod 0600 "$profile" || return 1
    prepared=$(core_config_prepare_value "$profile" MYSQL_ROOT_PASSWORD "${MYSQL_ROOT_PASSWORD:-}") || return 1
    [[ -n "$prepared" ]] || return 0
    trap '[[ -z "$prepared" ]] || secure_shred "$prepared"' EXIT
    backup=$(mktemp "${profile}.pre-root.XXXXXXXX") || return 1
    lemper_exec cp "$profile" "$backup" && lemper_exec chmod 0600 "$backup" || return 1
    lemper_exec mv -Tf "$prepared" "$profile" || return 1
    prepared=""
)

# Preserve the old option ordering while removing secrets from readable my.cnf.
# This storage migration does not depend on database availability or credentials.
function lemper_mariabackup_migrate_inline() (
    local main="$1" directory="$2" target="$2/.lemper-inline-mariabackup.cnf" stage="" clean="" backup original
    [[ "$directory" =~ ^/[a-zA-Z0-9_./-]+$ ]] || {
        error "Unsupported backup include directory."
        return 1
    }
    if ! lemper_db_directory_safe "$directory" || ! lemper_db_directory_safe "${main%/*}" \
        || [[ ! -f "$main" || -L "$main" || "$(stat -c %u "$main")" != "$EUID" ]]; then return 1; fi
    (((8#$(stat -c %a "$main") & 0022) == 0)) || return 1
    awk '
        /^[[:space:]]*\[/ { active=($0 ~ /^[[:space:]]*\[mariabackup\]/); next }
        active && NF && $0 !~ /^[[:space:]]*(#|;|user[[:space:]]*=|password[[:space:]]*=|open_files_limit[[:space:]]*=)/ { bad=1 }
        END { exit bad }
    ' "$main" || {
        error "Inline backup configuration requires explicit tuning reconciliation."
        return 1
    }
    if [[ -e "$target" || -L "$target" ]]; then
        [[ -f "$target" && ! -L "$target" && "$(stat -c %u "$target")" == "$EUID" ]] || return 1
        (((8#$(stat -c %a "$target") & 0022) == 0)) || return 1
        awk '/^[[:space:]]*\[/ && $0 !~ /^[[:space:]]*\[mariabackup\]/ { bad=1 } END { exit bad }' "$target" || return 1
        grep -q '^# Managed by LEMPer; migrated inline credentials.$' "$target" || return 1
    fi
    [[ "${DRYRUN:-false}" != true ]] || {
        info "Would migrate inline backup credentials."
        return 0
    }
    umask 077
    [[ -d "$directory" ]] || lemper_exec install -d -m0755 "$directory" || return 1
    stage=$(mktemp "$directory/.inline-backup.XXXXXXXX") || return 1
    clean=$(mktemp "${main}.inline-stage.XXXXXXXX") || {
        secure_shred "$stage"
        return 1
    }
    trap '[[ -z "$stage" ]] || secure_shred "$stage"; [[ -z "$clean" ]] || secure_shred "$clean"' EXIT
    printf '# Managed by LEMPer; migrated inline credentials.\n' >"$stage" || return 1
    awk '
        /^[[:space:]]*\[/ { active=($0 ~ /^[[:space:]]*\[mariabackup\]/) }
        active { print }
    ' "$main" >>"$stage" || return 1
    LEMPER_BACKUP_INCLUDE="$target" awk '
        /^[[:space:]]*\[/ {
            active=($0 ~ /^[[:space:]]*\[mariabackup\]/)
            if (active) { if (!included) print "!include " ENVIRON["LEMPER_BACKUP_INCLUDE"]; included=1; next }
        }
        !active { print }
    ' "$main" >"$clean" || return 1
    for original in "$main" "$target"; do
        [[ -f "$original" ]] || continue
        backup=$(mktemp "${original}.pre-inline.XXXXXXXX") || return 1
        lemper_exec cp "$original" "$backup" && lemper_exec chmod 0600 "$backup" || return 1
    done
    lemper_exec chmod 0600 "$stage" || return 1
    lemper_exec chown --reference="$main" "$clean" || return 1
    lemper_exec chmod --reference="$main" "$clean" || return 1
    lemper_exec mv -Tf "$stage" "$target" || return 1
    stage=""
    lemper_exec mv -Tf "$clean" "$main" || return 1
    clean=""
)

# Keep the private include at the original option-precedence position. Copy only
# credential keys, so later tuning includes are not overridden by replayed tuning.
function lemper_mariabackup_sync_inline() (
    local source="$1" target="$2" stage=""
    [[ -f "$source" && ! -L "$source" && "$(stat -c %u "$source")" == "$EUID" ]] || return 1
    lemper_db_directory_safe "${target%/*}" || return 1
    [[ ! -L "$target" ]] || return 1
    if [[ -e "$target" ]]; then
        [[ -f "$target" && "$(stat -c %u "$target")" == "$EUID" ]] || return 1
        (((8#$(stat -c %a "$target") & 0022) == 0)) || return 1
        grep -q '^# Managed by LEMPer; migrated inline credentials.$' "$target" || return 1
    fi
    [[ "${DRYRUN:-false}" != true ]] || {
        info "Would synchronize migrated backup credentials."
        return 0
    }
    umask 077
    stage=$(mktemp "${target}.XXXXXXXX") || return 1
    trap '[[ -z "$stage" ]] || secure_shred "$stage"' EXIT
    {
        printf '# Managed by LEMPer; migrated inline credentials.\n[mariabackup]\n'
        awk '
            /^[[:space:]]*\[/ { active=($0 ~ /^[[:space:]]*\[mariabackup\]/); next }
            active && /^[[:space:]]*(user|password|open_files_limit)[[:space:]]*=/ { print }
        ' "$source"
    } >"$stage" || return 1
    lemper_exec chmod 0600 "$stage" || return 1
    lemper_exec mv -Tf "$stage" "$target" || return 1
    stage=""
)

function lemper_mariabackup_provision() (
    set -o pipefail
    local user="${MARIABACKUP_USER:-lemperdb}" password="${MARIABACKUP_PASS:-}"
    local legacy_user="${MARIABACKUP_USERNAME:-}" legacy_password="${MARIABACKUP_PASSWORD:-}"
    local directory="${LEMPER_MYSQL_CONFIG_DIR:-/etc/mysql/mariadb.conf.d}"
    local profile="${LEMPER_MARIADB_PROFILE:-/etc/lemper/lemper.conf}" target stage="" profile_stage="" prepared="" backup
    local exists defaults option old_user="" old_password="" sql_password input
    local main="${LEMPER_MYSQL_MAIN_CONFIG:-/etc/mysql/my.cnf}" inline=false migrated="$directory/.lemper-inline-mariabackup.cnf"
    lemper_load_module services/mariadb/database || return 1
    lemper_load_module core/config-update || return 1
    if [[ -n "$legacy_user" ]]; then
        [[ "$user" == lemperdb || "$user" == "$legacy_user" ]] || {
            error "Conflicting MariaDB backup account names."
            return 1
        }
        user="$legacy_user"
    fi
    if [[ -n "$legacy_password" ]]; then
        [[ -z "$password" || "$password" == "$legacy_password" ]] || {
            error "Conflicting MariaDB backup credentials."
            return 1
        }
        password="$legacy_password"
    fi
    [[ "$user" != root && ${#user} -le 32 && "$user" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || {
        error "Invalid MariaDB backup account name."
        return 1
    }
    if ! lemper_mariabackup_secret_valid "$password" || ! lemper_mariabackup_secret_valid "${MYSQL_ROOT_PASSWORD:-}"; then
        error "MariaDB credentials must be single-line values without control characters."
        return 1
    fi
    if ! lemper_db_directory_safe "$directory" || ! lemper_db_directory_safe "${profile%/*}"; then
        error "Unsafe MariaDB configuration directory."
        return 1
    fi
    target="$directory/50-mariabackup.cnf"
    [[ ! -L "$target" && ! -L "$profile" ]] || {
        error "Refusing symlink credential configuration."
        return 1
    }
    if [[ "${DRYRUN:-false}" == true ]]; then
        info "Would reconcile the MariaDB backup account and protected configuration."
        return 0
    fi
    [[ -f "$profile" && "$(stat -c %u "$profile")" == "$EUID" ]] || {
        error "A trusted installed LEMPer configuration is required."
        return 1
    }
    (((8#$(stat -c %a "$profile") & 0022) == 0)) || {
        error "Refusing writable installed credentials."
        return 1
    }
    lemper_exec chmod 0600 "$profile" || return 1
    # Older installers appended the same group to my.cnf. Resolve legitimate
    # distribution symlinks, and retire only that group after protecting a backup.
    if [[ -e "$main" ]]; then
        main=$(readlink -f "$main") || return 1
        lemper_db_directory_safe "${main%/*}" || return 1
        [[ -f "$main" && "$(stat -c %u "$main")" == "$EUID" ]] || return 1
        (((8#$(stat -c %a "$main") & 0022) == 0)) || return 1
        if grep -qE '^[[:space:]]*\[mariabackup\]' "$main"; then
            inline=true
            lemper_mariabackup_migrate_inline "$main" "$directory" || return 1
        fi
        if grep -qFx "!include $migrated" "$main"; then
            inline=true
            if [[ ! -e "$migrated" ]]; then
                lemper_mariabackup_sync_inline "$target" "$migrated" || return 1
            fi
            [[ -f "$migrated" && ! -L "$migrated" && "$(stat -c %u "$migrated")" == "$EUID" ]] || return 1
            (((8#$(stat -c %a "$migrated") & 0022) == 0)) || return 1
            lemper_exec chmod 0600 "$migrated" || return 1
        fi
    fi
    input="$target"
    [[ "$inline" != true ]] || input="$main"
    if [[ -e "$target" ]]; then
        [[ -f "$target" && "$(stat -c %u "$target")" == "$EUID" ]] || return 1
        (((8#$(stat -c %a "$target") & 0022) == 0)) || {
            error "Refusing writable legacy backup credentials."
            return 1
        }
        # The dedicated legacy drop-in may contain tuning, but never other groups.
        awk '/^[[:space:]]*\[/ && $0 !~ /^[[:space:]]*\[mariabackup\]/ { bad=1 } END { exit bad }' "$target" || {
            error "Backup drop-in contains unrelated configuration groups."
            return 1
        }
        # Protect trusted legacy credentials even if authentication later fails.
        lemper_exec chmod 0600 "$target" || return 1
    fi
    if [[ -f "$input" ]]; then
        lemper_load_module services/mariadb/option_guard || return 1
        lemper_mariadb_option_guard "$input" || return 1
        defaults=$(my_print_defaults --defaults-file="$input" mariabackup 2>/dev/null) || {
            error "Cannot parse legacy MariaDB backup configuration."
            return 1
        }
        while IFS= read -r option; do
            [[ -n "$option" ]] || continue
            [[ "$option" == --* && ! "$option" =~ [[:cntrl:]] ]] || {
                error "Unsupported legacy option output."
                return 1
            }
            case "$option" in --user=*) old_user="${option#*=}" ;; --password=*) old_password="${option#*=}" ;; esac
        done <<<"$defaults"
        [[ -z "$old_user" || "$old_user" == "$user" ]] || {
            error "Backup drop-in belongs to a different account."
            return 1
        }
        [[ -n "$password" ]] || password="$old_password"
        lemper_mariabackup_secret_valid "$password" || return 1
    fi
    exists=$(MYSQL_PWD="${MYSQL_ROOT_PASSWORD:-}" mariadb --user=root --host=localhost --batch --skip-column-names \
        -e "SELECT COUNT(*) FROM mysql.user WHERE User='$user' AND Host='localhost';" 2>/dev/null) || {
        error "Cannot inspect MariaDB backup account state."
        return 1
    }
    [[ "$exists" == 0 || "$exists" == 1 ]] || return 1
    if [[ "$exists" == 1 ]]; then
        if [[ -z "$password" ]] || ! MYSQL_PWD="$password" mariadb --user="$user" --host=localhost \
            -e 'SELECT 1;' >/dev/null 2>&1; then
            error "Existing backup account requires working credentials; its password was not changed."
            return 1
        fi
    elif [[ -z "$password" ]]; then
        password=$(openssl rand -hex 24) || return 1
    fi
    umask 077
    [[ -d "$directory" ]] || lemper_exec install -d -m0755 "$directory" || return 1
    stage=$(mktemp "$directory/.mariabackup.XXXXXXXX") || return 1
    profile_stage=$(mktemp "${profile}.backup-stage.XXXXXXXX") || {
        rm -f "$stage"
        return 1
    }
    trap '[[ -z "$stage" ]] || secure_shred "$stage"; [[ -z "$profile_stage" ]] || secure_shred "$profile_stage"; [[ -z "$prepared" ]] || secure_shred "$prepared"' EXIT
    {
        printf '# Managed by LEMPer; backup credentials.\n[mariabackup]\n'
        if [[ -f "$target" ]]; then
            awk '!/^[[:space:]]*(\[|user[[:space:]]*=|password[[:space:]]*=|open_files_limit[[:space:]]*=|#|;)/ && NF' "$target"
        fi
        # Includes can select another group or older credentials. Re-enter the
        # backup group and make verified credentials authoritative after tuning.
        printf '[mariabackup]\nuser='
        lemper_mariabackup_quote_option "$user"
        printf '\npassword='
        lemper_mariabackup_quote_option "$password"
        printf '\nopen_files_limit=65535\n'
    } >"$stage" || return 1
    lemper_exec cp "$profile" "$profile_stage" || return 1
    local key value
    local keys=(MARIABACKUP_USER MARIABACKUP_PASS MARIABACKUP_USERNAME MARIABACKUP_PASSWORD)
    [[ -z "${MYSQL_ROOT_PASSWORD:-}" ]] || keys+=(MYSQL_ROOT_PASSWORD)
    for key in "${keys[@]}"; do
        case "$key" in MARIABACKUP_USER) value="$user" ;; MARIABACKUP_PASS) value="$password" ;; MYSQL_ROOT_PASSWORD) value="$MYSQL_ROOT_PASSWORD" ;; *) value="" ;; esac
        # The shared writer protects actual leading/trailing quote pairs.
        prepared=$(core_config_prepare_value "$profile_stage" "$key" "$value") || return 1
        [[ -z "$prepared" ]] || lemper_exec mv -Tf "$prepared" "$profile_stage" || return 1
        prepared=""
    done
    # Keep protected recovery copies before publishing either representation.
    local originals=("$profile" "$target")
    for option in "${originals[@]}"; do
        [[ -f "$option" ]] || continue
        backup=$(mktemp "${option}.pre-backup.XXXXXXXX") || return 1
        lemper_exec cp "$option" "$backup" && lemper_exec chmod 0600 "$backup" || return 1
    done
    lemper_exec chmod 0600 "$stage" "$profile_stage" || return 1
    lemper_exec mv -Tf "$profile_stage" "$profile" || return 1
    profile_stage=""
    lemper_exec mv -Tf "$stage" "$target" || return 1
    stage=""
    [[ "$inline" != true ]] || lemper_mariabackup_sync_inline "$target" "$migrated" || return 1
    # Credentials are durable before SQL mutation. If creation/grants fail,
    # retain them for a safe retry; never delete or reset a pre-existing account.
    sql_password=$(lemper_db_password_sql "$password") || return 1
    if ! {
        printf "SET SESSION sql_mode='NO_BACKSLASH_ESCAPES';\n"
        [[ "$exists" != 0 ]] || printf "CREATE USER '%s'@'localhost' IDENTIFIED BY %s;\n" "$user" "$sql_password"
        printf "GRANT RELOAD, PROCESS, LOCK TABLES, REPLICATION CLIENT ON *.* TO '%s'@'localhost';\n" "$user"
    } | MYSQL_PWD="${MYSQL_ROOT_PASSWORD:-}" mariadb --user=root --host=localhost >/dev/null 2>&1; then
        error "MariaDB backup provisioning failed; protected credentials are retained for retry."
        return 1
    fi
    success "MariaDB backup account reconciled; credentials are protected."
)
