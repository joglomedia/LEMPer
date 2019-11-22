#!/bin/bash

set -e

## Version control ##

APP_NAME=$(basename "$0")
APP_VERSION="1.0.0"
CMD_PARENT="lemper-cli"
CMD_NAME="db"


## Decorator ##

RED=91
GREEN=92
YELLOW=93

function begin_color() {
    color="${1}"
    echo -e -n "\e[${color}m"
}

function end_color() {
    echo -e -n "\e[0m"
}

function echo_color() {
    color="${1}"
    shift
    begin_color "$color"
    echo "$@"
    end_color
}

function error() {
    #local error_message="$@"
    echo_color "$RED" -n "Error: " >&2
    echo "$@" >&2
}

# Prints an error message and exits with an error code.
function fail() {
    error "$@"

    # Normally I'd use $0 in "usage" here, but since most people will be running
    # this via curl, that wouldn't actually give something useful.
    echo >&2
    echo "For usage information, run this script with --help" >&2
    exit 1
}

function status() {
    echo_color "$GREEN" "$@"
}

function warning() {
    echo_color "$YELLOW" "$@"
}

# If we set -e or -u then users of this script will see it silently exit on
# failure.  Instead we need to check the exit status of each command manually.
# The run function handles exit-status checking for system-changing commands.
# Additionally, this allows us to easily have a dryrun mode where we don't
# actually make any changes.
function run() {
    if "${DRYRUN}"; then
        echo_color "$YELLOW" -n "would run "
        echo "$@"
    else
        if ! "$@"; then
            local CMDSTR="$*"
            error "Failure running '${CMDSTR}', exiting."
            exit 1
        fi
    fi
}

# May need to run this as sudo!
# I have it in /usr/local/bin and run command 'ngxvhost' from anywhere, using sudo.
if [ "$(id -u)" -ne 0 ]; then
    error "This command can only be used by root."
    exit 1  #error
fi


## Helper Functions.

# Trim whitespace.
# Ref: https://stackoverflow.com/a/3352015/12077262
function str_trim() {
    local str="$*"

    # Remove leading whitespace characters.
    str="${str#"${str%%[![:space:]]*}"}"

    # Remove trailing whitespace characters.
    str="${str%"${str##*[![:space:]]}"}"

    echo -n "${str}"
}

# Convert string to uppercase.
# Ref: https://unix.stackexchange.com/a/51987
function str_to_upper() {
    local str="$*"

    printf '%s\n' "${str}" | awk '{ print toupper($0) }'
}


## Main Functions.

function cmd_help() {
    cat <<- _EOF_
${APP_NAME^} ${APP_VERSION}
Command line database management tool for LEMPer stack.

Usage: ${CMD_PARENT} ${CMD_NAME} [--version] [--help]
       <command> [<options>]

Default options are read from the following files in the given order:
/etc/lemper/lemper.conf

These are common ${CMD_PARENT} ${CMD_NAME} subcommands used in various situations:
  account       Creates a new user account.
  create        Creates a new database.
  databases     Lists the databases.
  drop          Deletes the existing database.
  export        Exports the database to a file or to STDOUT.
  import        Imports a database from a file or from STDIN.
  optimize      Optimizes the database.
  query         Executes a SQL query against the database.
  repair        Repairs the database.
  reset         Removes all tables from the database.
  search        Finds a string in the database.
  size          Displays the database name and size.
  tables        Lists the database tables.

For help with each command run:
${CMD_PARENT} ${CMD_NAME} <command> -h|--help
_EOF_

    exit 0
}

function cmd_version() {
    echo "${CMD_PARENT} ${CMD_NAME} version ${APP_VERSION}"
    exit 0
}

function cmd_account() {
    db_ops "--action=account" "$@"
}

function cmd_create() {
    db_ops "--action=create" "$@"
}

function cmd_databases() {
    db_ops "--action=databases" "$@"
}

function cmd_drop() {
    db_ops "--action=drop" "$@"
}

function cmd_export() {
    db_ops "--action=export" "$@"
}

function cmd_import() {
    db_ops "--action=import" "$@"
}

function cmd_optimize() {
    echo "Optimizes the database."
    db_ops "--action=optimize" "$@"
}

function cmd_query() {
    echo "Executes a SQL query against the database."
    db_ops "--action=query" "$@"
}

function cmd_repair() {
    echo "Repairs the database."
    db_ops "--action=repair" "$@"
}

function cmd_reset() {
    echo "Removes all tables from the database."
    db_ops "--action=reset" "$@"
}

function cmd_search() {
    echo "Finds a string in the database."
    db_ops "--action=search" "$@"
}

function cmd_size() {
    echo "Displays the database name and size."
    db_ops "--action=size" "$@"
}

function cmd_tables() {
    echo "Lists the database tables."
    db_ops "--action=tables" "$@"
}

function cmd_users() {
    echo "Lists users."
    db_ops "--action=users" "$@"
}

# Initialize account subcommand.
# 
function sub_cmd_account() {
    # account subcommands
    function cmd_account_help() {
        cat <<- _EOF_
${APP_NAME^} ${APP_VERSION}
Command line database management tool for LEMPer stack.

Usage: ${CMD_PARENT} ${CMD_NAME} account [--version] [--help]
       <command> [<options>]

Default options are read from the following files in the given order:
/etc/lemper/lemper.conf

These are common ${CMD_PARENT} ${CMD_NAME} account subcommands used in various situations:
  access    Grants privileges to the existing user account.
  create    Creates a new user account.
  delete    Deletes the existing user account.
  passwd    Updates password for the existing user account.
  rename    Renames the existing user account.
  revoke    Revokes privileges from the existing user account.

For help with each command run:
${CMD_PARENT} ${CMD_NAME} account <command> -h|--help
_EOF_

        exit 0
    }

    function cmd_account_version() {
        echo "${CMD_PARENT} ${CMD_NAME} account version ${APP_VERSION}"
        exit 0
    }

    # Creates a new account.
    function cmd_account_create() {
        if [ "${DBUSER}" != "root" ]; then
            DBUSER=${DBUSER:-"${LEMPER_USERNAME}_$(openssl rand -base64 32 | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)"}
            DBPASS=${DBPASS:-"$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"}

            # Create database account.
            if mysql -u root -p"${MYSQL_ROOT_PASS}" -e "SELECT User FROM mysql.user WHERE user='${DBUSER}';" | grep -qwE "${DBUSER}"; then
                error "MySQL account ${DBUSER} is already exist. Please use another one!"
            else
                echo "Creating new MySQL account '${DBUSER}'@'${DBHOST}' using password ${DBPASS}..."
                run mysql -u root -p"${MYSQL_ROOT_PASS}" -e "CREATE USER '${DBUSER}'@'${DBHOST}' IDENTIFIED BY '${DBPASS}';"

                if mysql -u root -p"${MYSQL_ROOT_PASS}" -e "SELECT User FROM mysql.user WHERE user='${DBUSER}';" | grep -qwE "${DBUSER}"; then
                    status -n "Success: "; echo "A new database account has been created."
                    echo -e "Below the account details:\nUsername: ${DBUSER}\nPassword: ${DBPASS}\nHost: ${DBHOST}"
                fi
            fi
        else
            error "Root user is already exist. Please use another one!"
        fi
    }

    # Aliases to create.
    function cmd_account_add() {
        cmd_account_create "$@"
    }

    # Aliases to create.
    function cmd_account_new() {
        cmd_account_create "$@"
    }

    # Deletes an existing account.
    function cmd_account_delete() {
        if [ -z "${DBUSER}" ]; then
            fail "Please specify the account's username using --dbuser parameter."
        fi

        if [[ "${DBUSER}" = "root" || "${DBUSER}" = lemper* ]]; then
            error "you're not allowed to delete this user."
        else
            if mysql -u root -p"${MYSQL_ROOT_PASS}" -e "DROP USER '${DBUSER}'@'${DBHOST}';"; then
                status -n "Success: "; echo "database account '${DBUSER}'@'${DBHOST}' has been deleted."
            else
                error "unable to delete database account '${DBUSER}'@'${DBHOST}'."
            fi
        fi
    }

    # Update password.
    function cmd_account_passwd() {
        DBHOST=${DBHOST:-"localhost"}
        DBUSER=${DBUSER:-""}
        DBPASS2=${DBPASS2:-"$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"}
        DBROOT_PASS=${DBROOTPASS:-"${MYSQL_ROOT_PASS}"}

        if [ -z "${DBUSER}" ]; then
            fail "Please specify the account's username using --dbuser parameter."
        fi

        if [ -z "${DBPASS2}" ]; then
            error "Please specify the new username to replace using --extra-args parameter."
            echo "An example for passing extra arguments: --extra-args=\"dbuser2=newuser,dbhost2=127.0.0.1\""
            exit 1
        fi

        local SQL_QUERY="UPDATE mysql.user SET Password=PASSWORD('${DBPASS2}') WHERE USER='${DBUSER}' AND Host='${DBHOST}';"
        if mysql -u root -p"${DBROOT_PASS}" -e "${SQL_QUERY}"; then
            status -n "Success: "
            echo "Password for account '${DBUSER}'@'${DBHOST}' has been updated to '${DBPASS2}'."
        else
            error "Unable to update password for '${DBUSER}'@'${DBHOST}'."
        fi
    }

    # Rename an existing account.
    function cmd_account_rename() {
        DBHOST2=${DBHOST2:-"${DBHOST}"}
        DBUSER2=${DBUSER2:-""}
        DBROOT_PASS=${DBROOTPASS:-"${MYSQL_ROOT_PASS}"}

        if [ -z "${DBUSER}" ]; then
            fail "Please specify the account's username using --dbuser parameter."
        fi

        if [ -z "${DBUSER2}" ]; then
            error "Please specify the new username to replace using --extra-args parameter."
            echo "An example for passing extra arguments: --extra-args=\"dbuser2=newuser,dbhost2=127.0.0.1\""
            exit 1
        fi

        if [[ "${DBUSER}" = "root" || "${DBUSER}" = lemper* ]]; then
            error "You are not allowed to rename this account."
        else
            if mysql -u root -p"${DBROOT_PASS}" -e "RENAME USER '${DBUSER}'@'${DBHOST}' TO '${DBUSER2}'@'${DBHOST2}';"; then
                status -n "Success: "
                echo "Database account '${DBUSER}'@'${DBHOST}' has been renamed to '${DBUSER2}'@'${DBHOST2}'."
            else
                error "Unable to rename database account '${DBUSER}'@'${DBHOST}'."
            fi
        fi
    }

    # Initialize account subcommand.
    function init_cmd_account() {
        local SUBCOMMAND && \
        SUBCOMMAND=$(str_trim "${1}")

        case "${SUBCOMMAND}" in
            "" | "-h" | "--help" | "help")
                cmd_account_help
            ;;

            "-v" | "--version" | "version")
                cmd_account_version
            ;;

            *)
                shift
                if declare -F "cmd_account_${SUBCOMMAND}" &>/dev/null; then
                    "cmd_account_${SUBCOMMAND}" "$@"
                else
                    echo "${CMD_PARENT} ${CMD_NAME} account: unrecognized command '${SUBCOMMAND}'" >&2
                    echo "Run '${CMD_PARENT} ${CMD_NAME} account --help' for a list of known commands." >&2
                    exit 1
                fi
            ;;
        esac
    }

    init_cmd_account "$@"
}

# Main database operations.
#
function db_ops() {
    OPTS=$(getopt -o a:H:u:p:n:P:C:g:f:q:x:Dcdeirhv \
      -l action:,dbhost:,dbuser:,dbpass:,dbname:,dbprefix:,dbcollation:,dbprivileges:,dbfile:,dbquery:,extra-args: \
      -l dry-run,root,help,version \
      -n "${CMD_PARENT} ${CMD_NAME}" -- "$@")

    eval set -- "${OPTS}"

    # Args counter
    local MAIN_ARGS=0
    local BYPASSED_ARGS=""

    # Parse flags
    while true
    do
        case "${1}" in
            -a | --action) shift
                local ACTION="${1}"
                MAIN_ARGS=$((MAIN_ARGS + 1))
                shift
            ;;
            -H | --dbhost) shift
                DBHOST=${1}
                shift
            ;;
            -u | --dbuser) shift
                DBUSER="${1}"
                #MAIN_ARGS=$((MAIN_ARGS + 1))
                shift
            ;;
            -p | --dbpass) shift
                DBPASS="${1}"
                #MAIN_ARGS=$((MAIN_ARGS + 1))
                shift
            ;;
            -n | --dbname) shift
                DBNAME="${1}"
                #MAIN_ARGS=$((MAIN_ARGS + 1))
                shift
            ;;
            -P | --dbprefix) shift
                DBPREFIX="${1}"
                shift
            ;;
            -C | --dbcollation) shift
                DBCOLLATION="${1}"
                shift
            ;;
            -g | --dbprivileges) shift
                DBPRIVILEGES="${1}"
                shift
            ;;
            -f | --dbfile) shift
                DBFILE="${1}"
                shift
            ;;
            -q | --dbquery) shift
                DBQUERY="${1}"
                shift
            ;;
            -D | --dry-run) shift
                DRYRUN=true
            ;;
            -r | --root) shift
                USE_ROOT=true
            ;;
            -h | --help) shift
                # bypass
                BYPASSED_ARGS="${BYPASSED_ARGS} --help"
            ;;
            -v | --version) shift
                # bypass
                BYPASSED_ARGS="${BYPASSED_ARGS} --version"
            ;;
            -x | --extra-args) shift
                EXTRA_ARGS="${1}"
                shift
            ;;
            --) shift
                break
            ;;
            *)
                fail "Invalid argument: ${1}"
                exit 1
            ;;
        esac
    done

    if [ ${MAIN_ARGS} -ge 1 ]; then
        # Set default value.
        DBHOST=${DBHOST:-"localhost"}
        DBUSER=${DBUSER:-""}
        DBPASS=${DBPASS:-""}
        DBNAME=${DBNAME:-""}
        DBPREFIX=${DBPREFIX:-""}
        DBCOLLATION=${DBCOLLATION:-""}
        DBPRIVILEGES=${DBPRIVILEGES:-""}
        DBFILE=${DBFILE:-""}
        DBQUERY=${DBQUERY:-""}
        DRYRUN=${DRYRUN:-false}
        USE_ROOT=${USE_ROOT:-false}

        # Parse and export extra arguments.
        EXTRA_ARGS=${EXTRA_ARGS:-""}
        if [ -n "${EXTRA_ARGS}" ]; then
            IFS=', ' read -r -a FIELDS <<< "${EXTRA_ARGS}"
            for FIELD in "${FIELDS[@]}"; do
                #export "${FIELD}"
                # Convert argument name to uppercase.
                IFS='= ' read -r -a ARG_PARTS <<< "${FIELD}"
                ARG=$(str_to_upper "${ARG_PARTS[0]}")
                VAL=${ARG_PARTS[1]}
                export "${ARG^^}=${VAL}"
            done
        fi

        # Ensure mysql command is available before performing database operations.
        if [[ -z $(command -v mysql) ]]; then
            fail "MySQL is required to perform database operations, but not available on your stack. Please install it first!"
        fi

        # Database operations based on supplied action argument.
        case "${ACTION}" in
            "create")
                DBUSER=${DBUSER:-"root"}
                DBPASS=${DBPASS:-""}
                [[ "${DBUSER}" = "root" && -z "${DBPASS}" ]] && DBPASS="${MYSQL_ROOT_PASS}"

                DBNAME=${DBNAME:-"${LEMPER_USERNAME}_db$(openssl rand -base64 32 | tr -dc 'a-z0-9' | fold -w 6 | head -n 1)"}

                # Create database name.
                echo "Create new MySQL database name '${DBNAME}'"

                until ! mysql -u root -p"${DBPASS}" -e "SHOW DATABASES;" | grep -qwE "${DBNAME}"; do
                    echo "Database ${DBNAME} already exist, try another one..."
                    DBNAME="${LEMPER_USERNAME}_db$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | fold -w 6 | head -n 1)"
                    echo "New auto-generated MySQL database name '${DBNAME}'"
                done

                local SQL_QUERY && \
                SQL_QUERY="CREATE DATABASE ${DBNAME}; GRANT ALL PRIVILEGES ON ${DBNAME}.* TO '${DBUSER}'@'${DBHOST}'; FLUSH PRIVILEGES;"
                run mysql -u root -p"${DBPASS}" -e "${SQL_QUERY}"

                if mysql -u root -p"${DBPASS}" -e "SHOW DATABASES LIKE '${DBNAME}';" | grep -qwE "${DBNAME}"; then
                    status -n "Success: "; echo "A ne database '${DBNAME}' created."
                else
                    error "failed creating database '${DBNAME}'."
                fi
            ;;

            "databases")
                DBUSER=${DBUSER:-"root"}
                DBPASS=${DBPASS:-""}
                [[ "${DBUSER}" = "root" && -z "${DBPASS}" ]] && DBPASS="${MYSQL_ROOT_PASS}"

                local DATABASES && \
                DATABASES=$(mysql -u "${DBUSER}" -p"${DBPASS}" -e "SHOW DATABASES;" | grep -vE "Database|mysql|*_schema")

                echo "List of databases granted to user ${DBUSER}"
                echo "----------------------------"

                if [[ -n "${DATABASES}" ]]; then
                    printf '%s\n' "${DATABASES}"
                else
                    echo "No database found."
                fi

                echo "----------------------------"
            ;;

            "drop")
                if [[ -z "${DBNAME}" ]]; then
                    fail "please specify the name of database using --dbname parameter."
                fi

                DBUSER=${DBUSER:-"root"}
                DBPASS=${DBPASS:-""}
                [[ "${DBUSER}" = "root" && -z "${DBPASS}" ]] && DBPASS="${MYSQL_ROOT_PASS}"

                if [ -d "/var/lib/mysql/${DBNAME}" ]; then
                    echo "Deleting database ${DBNAME}..."
                    run mysql -u "${DBUSER}" -p"${DBPASS}" -e "DROP DATABASE ${DBNAME};"

                    if ! mysql -u root -p"${DBPASS}" -e "SHOW DATABASES LIKE '${DBNAME}';" | grep -qwE "${DBNAME}"; then
                        status -n "Success: "; echo "Database '${DBNAME}' has been dropped."
                    else
                        error "failed deleting database '${DBNAME}'."
                    fi
                else
                    error "database ${DBNAME} not found."
                fi
            ;;

            "export")
                if [[ -z "${DBNAME}" ]]; then
                    fail "please specify the name of database using --dbname parameter."
                fi

                DBUSER=${DBUSER:-"root"}
                DBPASS=${DBPASS:-""}
                [[ "${DBUSER}" = "root" && -z "${DBPASS}" ]] && DBPASS="${MYSQL_ROOT_PASS}"

                DBFILE=${DBFILE:-"${DBNAME}_$(date '+%d-%m-%Y_%T').sql"}

                # Export database tables.
                echo "Exporting database ${DBNAME} tables..."

                if [[ -n $(command -v mysqldump) ]]; then
                    if mysql -u "${DBUSER}" -p"${DBPASS}" -e "SHOW DATABASES;" | grep -qwE "${DBNAME}"; then
                        run mysqldump -u "${DBUSER}" -p"${DBPASS}" --databases "${DBNAME}" > "${DBFILE}"
                        [ -f "${DBFILE}" ] && status -n "Success: "; echo "database ${DBNAME} exported to ${DBFILE}."
                    else
                        error "specified database '${DBNAME}' is not exist."
                    fi
                else
                    fail "mysqldump is required to export database, but not available on your stack. Please install it first!"
                fi
            ;;

            "import")
                if [[ -z "${DBNAME}" ]]; then
                    fail "please specify the name of database using --dbname parameter."
                fi

                DBUSER=${DBUSER:-"root"}
                DBPASS=${DBPASS:-""}
                [[ "${DBUSER}" = "root" && -z "${DBPASS}" ]] && DBPASS="${MYSQL_ROOT_PASS}"

                # Import database tables.
                echo "Importing database ${DBNAME} tables..."

                if [[ -n "${DBFILE}" && -e "${DBFILE}" ]]; then
                    if mysql -u "${DBUSER}" -p"${DBPASS}" -e "SHOW DATABASES;" | grep -qwE "${DBNAME}"; then
                        run mysql -u "${DBUSER}" -p"${DBPASS}" "${DBNAME}" < "${DBFILE}"
                        echo "Database file ${DBFILE} imported to ${DBNAME}."
                    else
                        error "specified database '${DBNAME}' is not exist."
                    fi
                else
                    error "please specifiy the database file (typically .sql) to import using --dbfile parameter."
                fi
            ;;

            "account")
                sub_cmd_account "$@" "${BYPASSED_ARGS}"
            ;;

            "users")
                DBUSER=${DBUSER:-"root"}
                DBPASS=${DBPASS:-""}
                [[ "${DBUSER}" = "root" && -z "${DBPASS}" ]] && DBPASS="${MYSQL_ROOT_PASS}"
                
                echo "List all users..."

                run mysql -u "${DBUSER}" -p"${DBPASS}" -e "SELECT user,host FROM mysql.user;"
            ;;

            *)
                fail "Something went wrong."
            ;;
        esac
    else
        echo "${CMD_PARENT} ${CMD_NAME}: missing required argument."
        echo "Try '${CMD_PARENT} ${CMD_NAME} --help' for more information."
    fi
}

## Init main App
#
function init_db_app() {
    local SUBCMD="${1}"
    case ${SUBCMD} in
        "" | "-h" | "--help" | "help")
            cmd_help
        ;;
        "-v" | "--version" | "version")
            cmd_version
        ;;
        *)
            shift
            if declare -F "cmd_${SUBCMD}" &>/dev/null; then
                "cmd_${SUBCMD}" "$@"
            else
                echo "${CMD_PARENT} ${CMD_NAME}: unrecognized command '${SUBCMD}'" >&2
                echo "Run '${APP_NAME} --help' for a list of known commands." >&2
                exit 1
            fi
        ;;
    esac
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_db_app "$@"
