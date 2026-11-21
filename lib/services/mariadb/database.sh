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



# Functions only. SQL values are validated before legacy account/database dispatch.
function lemper_db_validate() {
    local name value privilege
    for name in DBNAME DBPREFIX DBUSER DBUSER2 DBCOLLATION; do
        value="${!name:-}"
        [[ -n "$value" ]] || continue
        case "$name" in
            DBUSER|DBUSER2) [[ ${#value} -le 32 && "$value" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] ;;
            *) [[ ${#value} -le 64 && "$value" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] ;;
        esac || { error "Invalid database identifier ($name)."; return 1; }
    done
    for name in DBHOST DBHOST2; do
        value="${!name:-}"
        [[ -z "$value" || ( ${#value} -le 253 && "$value" =~ ^[A-Za-z0-9_.:%-]+$ ) ]] || {
            error "Invalid database host."; return 1;
        }
    done
    if [[ ! "${DBPORT:-3306}" =~ ^[0-9]{1,5}$ ]]; then
        error "Invalid database port."; return 1
    fi
    if (( 10#${DBPORT:-3306} < 1 || 10#${DBPORT:-3306} > 65535 )); then
        error "Invalid database port."; return 1
    fi
    if [[ -n "${DBPRIVILEGES:-}" ]]; then
        [[ "$DBPRIVILEGES" != ,* && "$DBPRIVILEGES" != *, ]] || return 1
        local privileges=()
        IFS=, read -r -a privileges <<< "$DBPRIVILEGES"
        for privilege in "${privileges[@]}"; do
            privilege="${privilege#"${privilege%%[![:space:]]*}"}"
            privilege="${privilege%"${privilege##*[![:space:]]}"}"
            case "${privilege^^}" in
                'ALL PRIVILEGES'|ALL|SELECT|INSERT|UPDATE|DELETE|CREATE|DROP|REFERENCES|INDEX|ALTER| \
                'CREATE TEMPORARY TABLES'|'LOCK TABLES'|'EXECUTE'|'CREATE VIEW'|'SHOW VIEW'| \
                'CREATE ROUTINE'|'ALTER ROUTINE'|EVENT|TRIGGER|USAGE) ;;
                *) error "Unsupported database privileges."; return 1 ;;
            esac
        done
    fi
    for name in DBPASS DBPASS2 DBROOTPASS; do
        value="${!name:-}"
        [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || {
            error "Database passwords must be single-line values."; return 1;
        }
    done
    for name in DBFILE DBPASS_FILE; do
        value="${!name:-}"
        [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || {
            error "Invalid database file path."; return 1;
        }
    done
}

# SQL literals use doubled quotes under an explicit NO_BACKSLASH_ESCAPES session.
function lemper_db_password_sql() {
    local password="$1"
    password="${password//\'/\'\'}"
    printf "'%s'" "$password"
}

# Every writable directory and ancestor must be trusted; root-owned sticky /tmp is allowed.
function lemper_db_directory_safe() {
    local directory="$1" cursor owner mode
    [[ "$directory" == /* ]] || return 1
    cursor="$directory"
    while [[ "$cursor" != / ]]; do
        if [[ -e "$cursor" || -L "$cursor" ]]; then
            [[ -d "$cursor" && ! -L "$cursor" ]] || return 1
            read -r owner mode < <(stat -c '%u %a' -- "$cursor") || return 1
            [[ "$owner" == "$EUID" ]] || return 1
            if (( (8#$mode & 0022) != 0 )); then
                [[ "$owner" == 0 && ( "$cursor" == /tmp || "$cursor" == /var/tmp ) ]] &&
                    (( (8#$mode & 01000) != 0 )) || return 1
            fi
        fi
        cursor="${cursor%/*}"
        [[ -n "$cursor" ]] || cursor=/
    done
}

# Preserve socket-authenticated local root; a remote host/custom port uses TCP.
function lemper_db_connection_args() {
    local -n db_connection_target="$1"
    local host="${DBHOST:-localhost}" port="${DBPORT:-3306}"
    db_connection_target=(-h "$host")
    if [[ "$host" != localhost || "$port" != 3306 ]]; then db_connection_target+=(-P "$port"); fi
}

function lemper_db_exists() {
    local databases user="${1:-${DBUSER:-root}}" password="${2:-${DBPASS:-}}"
    local connection=()
    lemper_db_connection_args connection
    databases=$(MYSQL_PWD="$password" "$MYSQLCLI" -u "$user" "${connection[@]}" -N -B -e 'SHOW DATABASES;') || {
        error "Cannot list databases."; return 1;
    }
    grep -Fxq -- "$DBNAME" <<< "$databases" || {
        error "The specified database does not exist."; return 1;
    }
}

function lemper_db_dump() (
    local user="${DBUSER:-root}" password="${DBPASS:-}"
    local format="$1" directory target temporary tool connection=()
    lemper_db_connection_args connection
    lemper_db_validate || return 1
    [[ -n "${DBNAME:-}" ]] || { error "Specify --dbname."; return 1; }
    if [[ "$format" == gzip ]]; then
        directory="${DBFILE:-/var/backups/lemper}"
        target=""
    else
        target="${DBFILE:-${DBNAME}_$(date -u '+%Y%m%d_%H%M%S').sql}"
        [[ "$target" == /* ]] || target="$PWD/$target"
        directory="${target%/*}"
    fi
    lemper_db_directory_safe "$directory" || { error "Unsafe database backup directory."; return 1; }
    [[ -z "$target" || ! -L "$target" ]] || { error "Refusing a symlink dump target."; return 1; }
    if [[ "${DRYRUN:-false}" == true ]]; then info "Would back up database '$DBNAME'."; return 0; fi
    tool=$(command -v mariadb-dump || command -v mysqldump) || {
        error "mysqldump/mariadb-dump is required to backup database."; return 1;
    }
    [[ "$user" != root || -n "${password:-}" ]] || password="${MYSQL_ROOT_PASSWORD:-}"
    lemper_db_exists "$user" "$password" || return 1
    umask 077
    lemper_exec mkdir -p -- "$directory" || return 1
    temporary=$(mktemp "$directory/.lemper-dump.XXXXXXXX") || return 1
    trap 'rm -f -- "$temporary"' EXIT
    set -o pipefail
    if [[ "$format" == gzip ]]; then
        target="$directory/${DBNAME}_$(date -u '+%Y%m%d_%H%M%S')_${temporary##*.}.sql.gz"
        MYSQL_PWD="$password" "$tool" -u "$user" "${connection[@]}" \
            --single-transaction --databases "$DBNAME" | gzip > "$temporary" || {
            error "Database dump failed; no backup was published."; return 1;
        }
    else
        MYSQL_PWD="$password" "$tool" -u "$user" "${connection[@]}" \
            --single-transaction --databases "$DBNAME" > "$temporary" || {
            error "Database dump failed; no export was published."; return 1;
        }
    fi
    [[ -s "$temporary" ]] || { error "Empty database dump."; return 1; }
    lemper_exec mv -T -- "$temporary" "$target" || return 1
    success "Database '$DBNAME' backed up to '$target' (mode 0600)."
)

function lemper_db_restore() (
    local user="${DBUSER:-root}" password="${DBPASS:-}"
    lemper_db_validate || return 1
    [[ -n "${DBNAME:-}" ]] || { error "Specify --dbname."; return 1; }
    [[ -f "${DBFILE:-}" && -r "$DBFILE" && ! -L "$DBFILE" ]] || {
        error "Backup file not found or not a readable regular file."; return 1;
    }
    if [[ "${DRYRUN:-false}" == true ]]; then info "Would restore database '$DBNAME'."; return 0; fi
    [[ "$user" != root || -n "${password:-}" ]] || password="${MYSQL_ROOT_PASSWORD:-}"
    lemper_db_exists "$user" "$password" || return 1
    set -o pipefail
    local connection=()
    lemper_db_connection_args connection
    local client=("$MYSQLCLI" -u "$user" "${connection[@]}" \
        --binary-mode=1 --local-infile=0 --one-database "$DBNAME")
    if [[ "$DBFILE" == *.gz ]]; then
        gzip -t -- "$DBFILE" || { error "Invalid gzip backup."; return 1; }
        gzip -dc -- "$DBFILE" | MYSQL_PWD="${password:-}" lemper_exec "${client[@]}" || {
            error "Database restore failed."; return 1;
        }
    else
        MYSQL_PWD="${password:-}" lemper_exec "${client[@]}" < "$DBFILE" || {
            error "Database restore failed."; return 1;
        }
    fi
    success "Database '$DBNAME' restored."
)

# Numeric five-field cron grammar, including lists/ranges/steps, with field bounds.
function lemper_db_schedule_valid() {
    local schedule="$1" field item base step lower upper index=0 fields=() items=()
    [[ "$schedule" != *$'\n'* && "$schedule" != *$'\r'* && "$schedule" != *%* ]] || return 1
    read -r -a fields <<< "$schedule"
    [[ ${#fields[@]} == 5 ]] || return 1
    local minimum=(0 0 1 1 0) maximum=(59 23 31 12 7)
    for field in "${fields[@]}"; do
        [[ "$field" =~ ^[0-9*/,-]+$ && "$field" != ,* && "$field" != *, ]] || return 1
        IFS=, read -r -a items <<< "$field"
        for item in "${items[@]}"; do
            base="$item"
            if [[ "$item" == */* ]]; then
                base="${item%%/*}"; step="${item#*/}"
                [[ "$step" =~ ^[0-9]{1,2}$ ]] && (( 10#$step > 0 && 10#$step <= maximum[index] )) || return 1
            fi
            [[ "$base" != '*' ]] || continue
            lower="$base"; upper="$base"
            if [[ "$base" == *-* ]]; then lower="${base%%-*}"; upper="${base#*-}"; fi
            [[ "$lower" =~ ^[0-9]{1,2}$ && "$upper" =~ ^[0-9]{1,2}$ ]] || return 1
            (( 10#$lower >= minimum[index] && 10#$upper <= maximum[index] && 10#$lower <= 10#$upper )) || return 1
        done
        index=$((index+1))
    done
}

function lemper_db_schedule() (
    local user="${DBUSER:-root}" password="${DBPASS:-}"
    lemper_db_validate || return 1
    [[ -n "${DBNAME:-}" ]] || { error "Specify --dbname."; return 1; }
    local schedule="${DBSCHEDULE:-0 2 * * *}" cron temporary credentials command password_file="" previous="" protected=""
    lemper_db_schedule_valid "$schedule" || { error "Invalid five-field backup schedule."; return 1; }
    # Cron filenames/arguments deliberately have a smaller grammar than interactive paths.
    [[ -z "${DBFILE:-}" || "$DBFILE" =~ ^/[A-Za-z0-9_./-]+$ ]] || {
        error "Scheduled backup directory must be an absolute path without spaces or shell characters."; return 1;
    }
    [[ "${DBHOST:-localhost}" =~ ^[A-Za-z0-9_.:-]+$ ]] || {
        error "Scheduled database host cannot contain wildcard characters."; return 1;
    }
    lemper_db_directory_safe "${DBFILE:-/var/backups/lemper}" || return 1
    if [[ "${DRYRUN:-false}" == true ]]; then info "Would schedule backup for '$DBNAME': $schedule"; return 0; fi
    command="/usr/local/bin/lemperctl db backup --dbname=$DBNAME --dbuser=$user --dbhost=${DBHOST:-localhost} --dbport=${DBPORT:-3306}"
    [[ -z "${DBFILE:-}" ]] || command+=" --dbfile=$DBFILE"
    umask 077
    temporary=$(mktemp) || return 1
    trap 'rm -f -- "$temporary"; [[ -z "$previous" ]] || rm -f -- "$previous"; [[ -z "$protected" ]] || rm -f -- "$protected"' EXIT
    if ! cron=$(crontab -l 2>"$temporary"); then
        grep -q 'no crontab for' "$temporary" || { error "Cannot read existing crontab."; return 1; }
        cron=""
    fi
    if [[ "$user" != root || -n "${password:-}" ]]; then
        credentials="${LEMPER_DB_CREDENTIAL_DIR:-/etc/lemper/backup-credentials}"
        [[ "$credentials" =~ ^/[A-Za-z0-9_./-]+$ ]] || return 1
        lemper_db_directory_safe "$credentials" || return 1
        lemper_exec install -d -m 0700 -- "$credentials" || return 1
        password_file="$credentials/$DBNAME-$user.pass"
        [[ ! -L "$password_file" ]] || { error "Refusing a symlink credential file."; return 1; }
        protected=$(mktemp "$credentials/.password.XXXXXXXX") || return 1
        printf '%s\n' "$password" > "$protected" || return 1
        if [[ -e "$password_file" ]]; then
            [[ -f "$password_file" ]] || return 1
            previous=$(mktemp "$credentials/.previous.XXXXXXXX") || return 1
            cp -- "$password_file" "$previous" || return 1
        fi
        command+=" --dbpass-file=$password_file"
    fi
    awk -v database="$DBNAME" '
        /\/lemper(-cli|ctl) db backup / {
            for (i=1;i<=NF;i++) if ($i == "--dbname=" database) next
        }
        NF { print }
    ' <<< "$cron" > "$temporary" || return 1
    printf '%s %s\n' "$schedule" "$command" >> "$temporary" || return 1
    if [[ -n "$password_file" ]]; then lemper_exec mv -T -- "$protected" "$password_file" || return 1; fi
    if ! lemper_exec crontab "$temporary"; then
        if [[ -n "$password_file" ]]; then
            if [[ -n "$previous" ]]; then
                lemper_exec mv -T -- "$previous" "$password_file" || { error "Cannot restore previous schedule credential."; return 1; }
            else lemper_exec rm -f -- "$password_file" || return 1; fi
        fi
        error "Cannot install database backup schedule."; return 1
    fi
    success "Backup scheduled for '$DBNAME': $schedule."
)
