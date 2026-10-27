#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Interactive TUI (Terminal User Interface)                  |
# +-------------------------------------------------------------------------+
# | A pure-Bash, menu-driven TUI for managing the LEMPer stack.             |
# | No external dependencies - uses ANSI escape sequences and read.         |
# |                                                                         |
# | Invoked as: lemper-cli tui  or  lemper-cli --interactive                |
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

# shellcheck disable=SC2034
CMD_PARENT="${PROG_NAME}"
# shellcheck disable=SC2034
CMD_NAME="tui"

# Make sure only root can access and not direct access.
if [[ "$(type -t requires_root)" != "function" ]]; then
    echo "Direct access to this script is not permitted."
    exit 1
fi

##
# TUI Color palette.
##
TUI_BG=44        # Blue background
TUI_FG=37        # White foreground
TUI_BORDER=34    # Green border
TUI_HIGHLIGHT=43 # Yellow highlight
TUI_DIM=90       # Dim/grey

##
# Clear screen.
##
function tui_clear() {
    printf '\033[2J\033[H'
}

##
# Print a colored line without newline.
##
function tui_print() {
    local color="${1}"
    shift
    printf '\033[%sm%s\033[0m' "${color}" "$*"
}

##
# Print a colored line with newline.
##
function tui_echo() {
    local color="${1}"
    shift
    printf '\033[%sm%s\033[0m\n' "${color}" "$*"
}

##
# Run a LEMPer CLI command from inside the TUI.
# Plugins are sourced by the CLI, so they cannot be executed directly.
##
function tui_cli() {
    local cli="${LEMPER_CLI_BIN:-}"

    if [[ -z "${cli}" ]]; then
        cli=$(command -v "${PROG_NAME:-lemper-cli}" 2>/dev/null || true)
    fi
    if [[ -z "${cli}" && -x /usr/local/bin/lemper-cli ]]; then
        cli="/usr/local/bin/lemper-cli"
    fi
    if [[ -z "${cli}" ]]; then
        tui_echo "${RED}" "  lemper-cli executable not found."
        return 1
    fi

    "${cli}" "$@"
}

##
# Draw a bordered box.
##
function tui_box() {
    local title="${1}"
    local width="${2:-60}"
    local border_char="─"

    # Top border
    tui_print "${TUI_BORDER}" ""
    printf '%*s\n' "${width}" "" | tr ' ' "${border_char}"

    # Title
    local title_line
    title_line=$(printf ' %s ' "${title}")
    tui_print "${TUI_BORDER}" "${border_char}"
    printf '%s' "${border_char}"
    tui_print "${TUI_BG}" "${title_line}"
    printf '%*s\n' "$((width - ${#title_line} - 1))" "" | tr ' ' "${border_char}"
    printf '\n'
    tui_print "${TUI_BORDER}" ""
    printf '%*s\n' "${width}" "" | tr ' ' "${border_char}"

    # Bottom border (drawn by caller)
}

##
# Draw a horizontal rule.
##
function tui_rule() {
    local width="${1:-60}"
    local char="${2:-─}"
    printf '%*s\n' "${width}" "" | tr ' ' "${char}"
}

##
# Display a menu with options.
# Arguments: title, prompt, options_array...
##
function tui_menu() {
    local title="${1}"
    shift 2
    local options=("$@")
    local count=${#options[@]}

    # Callers read the selection with choice=$(tui_menu ...). Everything
    # drawn here has to reach the terminal on stderr; stdout is only the
    # selection number. Mixing the menu into stdout hides the screen and
    # makes the number impossible to match.
    {
        tui_clear
        tui_echo "${TUI_BORDER}" "═══════════════════════════════════════════════════════════"
        tui_echo "${TUI_BG}"
        printf '  %-58s\n' " ${title}"
        tui_echo "${TUI_BORDER}" "═══════════════════════════════════════════════════════════"
        echo ""

        local i=1 opt label desc
        for opt in "${options[@]}"; do
            label="${opt%%|*}"
            desc="${opt#*|}"
            if [[ "${label}" == "${desc}" ]]; then
                tui_print "${TUI_HIGHLIGHT}" "  [${i}] "
                tui_echo "${TUI_FG}" "${label}"
            else
                tui_print "${TUI_HIGHLIGHT}" "  [${i}] "
                tui_echo "${TUI_FG}" "${label}"
                printf '      %*s' "$((60 - ${#label}))" ""
                tui_echo "${TUI_DIM}" "${desc}"
            fi
            i=$((i + 1))
        done

        echo ""
        tui_rule 60
        echo ""
    } >&2

    local choice
    if ! read -rp "  Select [1-${count}] or 'q' to quit: " choice; then
        echo 0
        return
    fi
    choice="${choice#"${choice%%[![:space:]]*}"}"
    choice="${choice%"${choice##*[![:space:]]}"}"
    echo "" >&2

    case "${choice}" in
        q | Q | quit | exit)
            echo 0
        ;;
        *)
            if [[ "${choice}" =~ ^[0-9]+$ ]] && \
               [[ "${choice}" -ge 1 ]] && \
               [[ "${choice}" -le "${count}" ]]; then
                echo "${choice}"
            else
                tui_echo "${TUI_DIM}" "  Invalid selection. Press Enter to continue..." >&2
                read -r || true
                echo -1
            fi
        ;;
    esac
}

##
# Display system status dashboard.
##
function tui_system_status() {
    tui_clear
    tui_echo "${TUI_BORDER}" "═══════════════════════════════════════════════════════════"
    tui_echo "${TUI_BG}"
    printf '  %-58s\n' " System Status"
    tui_echo "${TUI_BORDER}" "═══════════════════════════════════════════════════════════"
    echo ""

    # Nginx status.
    if command -v nginx &>/dev/null; then
        if pgrep -x nginx &>/dev/null; then
            tui_print "${TUI_HIGHLIGHT}" "  Nginx: "
            tui_echo "${GREEN}" "Running"
        else
            tui_print "${TUI_HIGHLIGHT}" "  Nginx: "
            tui_echo "${RED}" "Stopped"
        fi
    else
        tui_print "${TUI_HIGHLIGHT}" "  Nginx: "
        tui_echo "${YELLOW}" "Not installed"
    fi

    # PHP-FPM status.
    local php_version
    php_version=$(command -v php 2>/dev/null | head -1)
    if [[ -n "${php_version}" ]]; then
        tui_print "${TUI_HIGHLIGHT}" "  PHP: "
        tui_echo "${GREEN}" "$(php -v 2>/dev/null | head -1)"
    else
        tui_print "${TUI_HIGHLIGHT}" "  PHP: "
        tui_echo "${RED}" "Not found"
    fi

    # MariaDB/MySQL status.
    local mysqlcli
    mysqlcli=""
    if [[ -n $(command -v mariadb) ]]; then
        mysqlcli="mariadb"
    elif [[ -n $(command -v mysql) ]]; then
        mysqlcli="mysql"
    fi
    if [[ -n "${mysqlcli}" ]]; then
        if pgrep -x mysqld &>/dev/null; then
            tui_print "${TUI_HIGHLIGHT}" "  MariaDB/MySQL: "
            tui_echo "${GREEN}" "Running"
        else
            tui_print "${TUI_HIGHLIGHT}" "  MariaDB/MySQL: "
            tui_echo "${RED}" "Stopped"
        fi
    else
        tui_print "${TUI_HIGHLIGHT}" "  MariaDB/MySQL: "
        tui_echo "${YELLOW}" "Not installed"
    fi

    # Fail2ban status.
    if command -v fail2ban-client &>/dev/null; then
        if pgrep -x fail2ban-server &>/dev/null; then
            tui_print "${TUI_HIGHLIGHT}" "  Fail2ban: "
            tui_echo "${GREEN}" "Running"
        else
            tui_print "${TUI_HIGHLIGHT}" "  Fail2ban: "
            tui_echo "${RED}" "Stopped"
        fi
    else
        tui_print "${TUI_HIGHLIGHT}" "  Fail2ban: "
        tui_echo "${YELLOW}" "Not installed"
    fi

    # Redis/Valkey status.
    if pgrep -x redis-server &>/dev/null; then
        tui_print "${TUI_HIGHLIGHT}" "  Redis: "
        tui_echo "${GREEN}" "Running"
    elif pgrep -x valkey-server &>/dev/null; then
        tui_print "${TUI_HIGHLIGHT}" "  Valkey: "
        tui_echo "${GREEN}" "Running"
    else
        tui_print "${TUI_HIGHLIGHT}" "  Redis/Valkey: "
        tui_echo "${YELLOW}" "Not running"
    fi

    # Disk usage.
    echo ""
    tui_echo "${TUI_BORDER}" "───────────────────────────────────────────────────────────"
    tui_print "${TUI_HIGHLIGHT}" "  Disk Usage:"
    echo ""
    df -h / 2>/dev/null | while read -r line; do
        printf '  %s\n' "${line}"
    done | head -5
    tui_echo "${TUI_BORDER}" "───────────────────────────────────────────────────────────"

    # Memory usage.
    echo ""
    tui_print "${TUI_HIGHLIGHT}" "  Memory Usage:"
    echo ""
    free -h 2>/dev/null | head -3 | while read -r line; do
        printf '  %s\n' "${line}"
    done

    echo ""
    tui_echo "${TUI_DIM}" "  Press Enter to return to main menu..."
    read -r
}

##
# Display sites menu and list vhosts.
##
function tui_sites() {
    local choice
    while true; do
        choice=$(tui_menu "Virtual Host Management" "Select an action:" \
            "List all sites|Show all configured vhosts" \
            "Show site details|Display detailed config for a domain" \
            "Create new site|Create a new virtual host" \
            "Manage site|Show site modification options" \
            "Back to main menu|Return to dashboard")

        case "${choice}" in
            1)
                echo ""
                tui_clear
                tui_cli site-list --all 2>&1 || true
                echo ""
                tui_echo "${TUI_DIM}" "  Press Enter to continue..."
                read -r
            ;;
            2)
                local domain
                echo ""
                read -rp "  Enter domain name: " domain
                if [[ -n "${domain}" ]]; then
                    tui_clear
                    tui_cli site-show "${domain}" --all 2>&1 || true
                fi
                echo ""
                tui_echo "${TUI_DIM}" "  Press Enter to continue..."
                read -r
            ;;
            3)
                tui_site_create_wizard
            ;;
            4)
                tui_clear
                tui_cli site mod --help 2>&1 || true
                echo ""
                tui_echo "${TUI_DIM}" "  Press Enter to continue..."
                read -r
            ;;
            5)
                return
            ;;
            -1) ;;  # Invalid, loop continues
            0)
                return
            ;;
        esac
    done
}

##
# Prompt for a yes/no answer.
# Arguments: prompt, default (y or n)
##
function tui_confirm() {
    local prompt="${1}"
    local default="${2:-n}"
    local answer

    if [[ "${default}" == "y" ]]; then
        read -rp "  ${prompt} [Y/n]: " answer
        answer=${answer:-y}
    else
        read -rp "  ${prompt} [y/N]: " answer
        answer=${answer:-n}
    fi

    [[ "${answer}" == [yY]* ]]
}

##
# Pick the newest installed PHP version.
##
function tui_default_php_version() {
    local versions="" dir

    for dir in /etc/php/*/; do
        [[ -d "${dir}" ]] || continue
        versions+="$(basename "${dir}")"$'\n'
    done

    if [[ -n "${versions}" ]]; then
        printf '%s' "${versions}" | sort -V | tail -n 1
    else
        printf '%s\n' "${DEFAULT_PHP_VERSION:-8.5}"
    fi
}

##
# Guided site creation wizard.
##
function tui_site_create_wizard() {
    tui_clear
    tui_echo "${TUI_BORDER}" "═══════════════════════════════════════════════════════════"
    tui_echo "${TUI_BG}"
    printf '  %-58s\n' " Create New Site — Wizard"
    tui_echo "${TUI_BORDER}" "═══════════════════════════════════════════════════════════"
    echo ""
    tui_echo "${TUI_DIM}" "  Leave an answer empty to use the [default] or cancel."
    echo ""

    local domain
    while true; do
        read -rp "  Domain name: " domain

        if [[ -z "${domain}" ]]; then
            tui_echo "${TUI_DIM}" "  Site creation cancelled."
            tui_echo "${TUI_DIM}" "  Press Enter to continue..."
            read -r
            return
        fi

        if [[ "$(validate_fqdn "${domain}")" == "true" ]]; then
            break
        fi

        tui_echo "${RED}" "  '${domain}' is not a valid domain name."
    done

    # Framework selection.
    local frameworks=(default wordpress wordpress-ms laravel symfony codeigniter drupal phalcon roundcube mautic sendy)
    local framework_choice
    framework_choice=$(tui_menu "Website Framework" "Select a framework:" \
        "Vanilla PHP|Plain PHP application" \
        "WordPress|WordPress CMS" \
        "WordPress Multisite|WordPress network" \
        "Laravel|Laravel framework" \
        "Symfony|Symfony framework" \
        "CodeIgniter|CodeIgniter framework" \
        "Drupal|Drupal CMS" \
        "Phalcon|Phalcon framework" \
        "Roundcube|Webmail client" \
        "Mautic|Marketing automation" \
        "Sendy|Newsletter application" \
        "Cancel|Back to site management")

    if [[ "${framework_choice}" == "0" || "${framework_choice}" == "-1" || \
          "${framework_choice}" -gt "${#frameworks[@]}" ]]; then
        return
    fi

    local framework="${frameworks[$((framework_choice - 1))]}"

    # System user.
    local default_user="${LEMPER_USERNAME:-lemper}"
    local username
    read -rp "  System user [${default_user}]: " username
    username=${username:-${default_user}}

    if ! id -u "${username}" >/dev/null 2>&1; then
        tui_echo "${YELLOW}" "  User '${username}' does not exist, using '${default_user}'."
        username="${default_user}"
    fi

    # Web root.
    local default_webroot="/home/${username}/webapps/${domain}"
    local webroot
    read -rp "  Web root [${default_webroot}]: " webroot
    webroot=${webroot:-${default_webroot}}

    if [[ "${webroot}" != /* ]]; then
        tui_echo "${YELLOW}" "  Web root must be an absolute path, using '${default_webroot}'."
        webroot="${default_webroot}"
    fi

    # PHP version.
    local default_php
    default_php=$(tui_default_php_version)
    local php_version
    read -rp "  PHP version [${default_php}]: " php_version
    php_version=${php_version:-${default_php}}

    if [[ ! "${php_version}" =~ ^[0-9]+\.[0-9]+$ ]]; then
        tui_echo "${YELLOW}" "  Invalid PHP version, using '${default_php}'."
        php_version="${default_php}"
    fi

    # Optional features.
    local app_default="n"
    case "${framework}" in
        wordpress | wordpress-ms | laravel | symfony | codeigniter | drupal | phalcon | roundcube | mautic | sendy)
            app_default="y"
        ;;
    esac

    local install_app="n" enable_ssl="n" wildcard="n" fastcgi_cache="n" fail2ban="n"
    tui_confirm "Install ${framework} application files?" "${app_default}" && install_app="y"
    tui_confirm "Enable Let's Encrypt SSL?" "n" && enable_ssl="y"

    if [[ "${enable_ssl}" == "y" ]]; then
        tui_confirm "Issue a wildcard certificate (*.${domain}) via DNS-01?" "n" && wildcard="y"
    fi

    tui_confirm "Enable FastCGI cache?" "n" && fastcgi_cache="y"
    tui_confirm "Enable Fail2ban filter?" "n" && fail2ban="y"

    # Review.
    tui_clear
    tui_echo "${TUI_BORDER}" "═══════════════════════════════════════════════════════════"
    tui_echo "${TUI_BG}"
    printf '  %-58s\n' " Review Site Configuration"
    tui_echo "${TUI_BORDER}" "═══════════════════════════════════════════════════════════"
    echo ""
    printf '  %-20s %s\n' "Domain:" "${domain}"
    printf '  %-20s %s\n' "Framework:" "${framework}"
    printf '  %-20s %s\n' "System user:" "${username}"
    printf '  %-20s %s\n' "Web root:" "${webroot}"
    printf '  %-20s %s\n' "PHP version:" "${php_version}"
    printf '  %-20s %s\n' "Install app:" "${install_app}"
    printf '  %-20s %s\n' "SSL:" "${enable_ssl}"
    printf '  %-20s %s\n' "Wildcard SSL:" "${wildcard}"
    printf '  %-20s %s\n' "FastCGI cache:" "${fastcgi_cache}"
    printf '  %-20s %s\n' "Fail2ban:" "${fail2ban}"
    echo ""

    if ! tui_confirm "Create this site now?" "y"; then
        tui_echo "${TUI_DIM}" "  Site creation cancelled."
        tui_echo "${TUI_DIM}" "  Press Enter to continue..."
        read -r
        return
    fi

    local args=(create
        --domain-name="${domain}"
        --framework="${framework}"
        --username="${username}"
        --webroot="${webroot}"
        --php-version="${php_version}")

    [[ "${install_app}" == "y" ]] && args+=(--install-app)
    [[ "${enable_ssl}" == "y" ]] && args+=(--enable-ssl)
    [[ "${wildcard}" == "y" ]] && args+=(--wildcard-domain)
    [[ "${fastcgi_cache}" == "y" ]] && args+=(--enable-fastcgi-cache)
    [[ "${fail2ban}" == "y" ]] && args+=(--enable-fail2ban)

    echo ""
    tui_cli site "${args[@]}" 2>&1 || \
        tui_echo "${RED}" "  Site creation failed."

    echo ""
    tui_echo "${TUI_DIM}" "  Press Enter to continue..."
    read -r
}

##
# Stream a log file in real time until a key is pressed.
# Arguments: log file path, display label
##
function tui_follow_log() {
    local log_file="${1}"
    local label="${2:-${log_file}}"

    if [[ ! -f "${log_file}" ]]; then
        tui_clear
        tui_echo "${YELLOW}" "  Log file not found: ${log_file}"
        tui_echo "${TUI_DIM}" "  Press Enter to continue..."
        read -r
        return
    fi

    local rows visible
    rows=$(tput lines 2>/dev/null || echo 24)
    visible=$((rows - 7))
    [[ "${visible}" -lt 5 ]] && visible=5

    while true; do
        tui_clear
        tui_echo "${TUI_BORDER}" "═══════════════════════════════════════════════════════════"
        tui_echo "${TUI_BG}"
        printf '  %-58s\n' " Live Logs — ${label}"
        tui_echo "${TUI_BORDER}" "═══════════════════════════════════════════════════════════"
        tui_echo "${TUI_DIM}" "  ${log_file}"
        tui_rule 60
        tail -n "${visible}" "${log_file}" 2>/dev/null || true
        tui_rule 60
        tui_echo "${TUI_DIM}" "  Refreshing every second — press 'q' or any key to stop."

        if read -r -s -n 1 -t 1 _; then
            break
        fi
    done

    tui_echo "${TUI_DIM}" "  Log stream stopped. Press Enter to continue..."
    read -r
}

##
# Display log streaming menu.
##
function tui_logs() {
    local choice log_file label

    while true; do
        choice=$(tui_menu "Live Logs" "Select a log to stream:" \
            "Nginx access|HTTP requests" \
            "Nginx error|Web server errors" \
            "PHP-FPM|PHP process manager log" \
            "MariaDB/MySQL|Database server log" \
            "Authentication|System login attempts" \
            "Fail2ban|Intrusion prevention log" \
            "Back to main menu|Return to dashboard")

        log_file=""
        label=""

        case "${choice}" in
            1) log_file="/var/log/nginx/access.log"; label="Nginx access" ;;
            2) log_file="/var/log/nginx/error.log"; label="Nginx error" ;;
            3)
                # Pick the newest installed PHP-FPM log.
                local php_logs=(/var/log/php*-fpm.log)
                if [[ -e "${php_logs[0]}" ]]; then
                    log_file=$(printf '%s\n' "${php_logs[@]}" | sort -V | tail -n 1)
                fi
                label="PHP-FPM"
            ;;
            4)
                if [[ -f /var/log/mysql/error.log ]]; then
                    log_file="/var/log/mysql/error.log"
                else
                    log_file="/var/log/mariadb/mariadb.log"
                fi
                label="MariaDB/MySQL"
            ;;
            5) log_file="/var/log/auth.log"; label="Authentication" ;;
            6) log_file="/var/log/fail2ban.log"; label="Fail2ban" ;;
            7 | 0) return ;;
            -1) continue ;;
            *) continue ;;
        esac

        if [[ -z "${log_file}" ]]; then
            tui_echo "${YELLOW}" "  No log file found for ${label}."
            tui_echo "${TUI_DIM}" "  Press Enter to continue..."
            read -r
            continue
        fi

        tui_follow_log "${log_file}" "${label}"
    done
}

##
# Display databases menu.
##
function tui_databases() {
    local choice
    while true; do
        choice=$(tui_menu "Database Management" "Select an action:" \
            "List databases|Show all MySQL/MariaDB databases" \
            "Backup database|Create timestamped sql.gz backup" \
            "Restore database|Restore from a backup file" \
            "Schedule backup|Add cron entry for automated backup" \
            "Back to main menu|Return to dashboard")

        case "${choice}" in
            1)
                echo ""
                tui_cli db databases 2>&1 || true
                echo ""
                tui_echo "${TUI_DIM}" "  Press Enter to continue..."
                read -r
            ;;
            2)
                local dbname
                echo ""
                read -rp "  Enter database name: " dbname
                if [[ -n "${dbname}" ]]; then
                    tui_cli db backup --dbname="${dbname}" 2>&1 || true
                fi
                echo ""
                tui_echo "${TUI_DIM}" "  Press Enter to continue..."
                read -r
            ;;
            3)
                local dbname dbfile
                echo ""
                read -rp "  Enter database name: " dbname
                read -rp "  Enter backup file path: " dbfile
                if [[ -n "${dbname}" && -n "${dbfile}" ]]; then
                    tui_cli db restore --dbname="${dbname}" --dbfile="${dbfile}" 2>&1 || true
                fi
                echo ""
                tui_echo "${TUI_DIM}" "  Press Enter to continue..."
                read -r
            ;;
            4)
                local dbname schedule
                echo ""
                read -rp "  Enter database name: " dbname
                read -rp "  Cron schedule (default: 0 2 * * *): " schedule
                if [[ -n "${dbname}" ]]; then
                    if [[ -n "${schedule}" ]]; then
                        tui_cli db backup-schedule --dbname="${dbname}" --dbschedule="${schedule}" 2>&1 || true
                    else
                        tui_cli db backup-schedule --dbname="${dbname}" 2>&1 || true
                    fi
                fi
                echo ""
                tui_echo "${TUI_DIM}" "  Press Enter to continue..."
                read -r
            ;;
            5)
                return
            ;;
            -1) ;;
            0)
                return
            ;;
        esac
    done
}

##
# Display security menu.
##
function tui_security() {
    local choice
    while true; do
        choice=$(tui_menu "Security & Firewall" "Select an action:" \
            "Firewall status|Check UFW/CSF/APF rules" \
            "Fail2ban status|Check Fail2ban jails and bans" \
            "CrowdSec status|Check CrowdSec decisions and alerts" \
            "SSL certificate status|Check certificate expiration" \
            "Back to main menu|Return to dashboard")

        case "${choice}" in
            1)
                echo ""
                if command -v ufw &>/dev/null; then
                    ufw status 2>&1 || true
                elif command -v csf &>/dev/null; then
                    csf -l 2>&1 | head -20 || true
                else
                    tui_echo "${YELLOW}" "  No firewall manager found."
                fi
                echo ""
                tui_echo "${TUI_DIM}" "  Press Enter to continue..."
                read -r
            ;;
            2)
                echo ""
                if command -v fail2ban-client &>/dev/null; then
                    fail2ban-client status 2>&1 || true
                    echo ""
                    tui_echo "${TUI_DIM}" "  Press Enter for jail details, or Ctrl+C to continue..."
                    read -r
                    fail2ban-client status sshd 2>&1 || true
                else
                    tui_echo "${YELLOW}" "  Fail2ban is not installed."
                fi
                echo ""
                tui_echo "${TUI_DIM}" "  Press Enter to continue..."
                read -r
            ;;
            3)
                echo ""
                if command -v cscli &>/dev/null; then
                    echo "  CrowdSec metrics:"
                    cscli metrics 2>&1 | head -20 || true
                    echo ""
                    echo "  CrowdSec alerts:"
                    cscli alerts list 2>&1 | head -20 || true
                elif command -v crowdsec-cli &>/dev/null; then
                    echo "  CrowdSec status:"
                    crowdsec-cli status 2>&1 | head -20 || true
                else
                    tui_echo "${YELLOW}" "  CrowdSec is not installed."
                fi
                echo ""
                tui_echo "${TUI_DIM}" "  Press Enter to continue..."
                read -r
            ;;
            4)
                echo ""
                if [[ -d /etc/letsencrypt/live ]]; then
                    local certs
                    certs=$(find /etc/letsencrypt/live -name "cert.pem" -exec dirname {} \; 2>/dev/null)
                    if [[ -n "${certs}" ]]; then
                        echo "  Certificate expiration:"
                        echo "  ─────────────────────"
                        while IFS= read -r cert_dir; do
                            local cn
                            cn=$(echo "${cert_dir}" | xargs basename 2>/dev/null)
                            local expiry
                            expiry=$(openssl x509 -in "${cert_dir}/cert.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
                            printf '  %-30s %s\n' "${cn}" "${expiry:-Unknown}"
                        done <<< "${certs}"
                    else
                        tui_echo "${YELLOW}" "  No Let's Encrypt certificates found."
                    fi
                else
                    tui_echo "${YELLOW}" "  /etc/letsencrypt/live not found."
                fi
                echo ""
                tui_echo "${TUI_DIM}" "  Press Enter to continue..."
                read -r
            ;;
            5)
                return
            ;;
            -1) ;;
            0)
                return
            ;;
        esac
    done
}

##
# Performance benchmark menu.
##
function tui_bench() {
    local choice
    while true; do
        choice=$(tui_menu "Performance Benchmark" "Select a test:" \
            "Quick benchmark|Hardware and disk I/O (no downloads)" \
            "Network speed test|Download test files from global endpoints" \
            "Full benchmark|Hardware, disk I/O, and network speed" \
            "Back to main menu|Return to dashboard")

        case "${choice}" in
            1)
                tui_clear
                tui_cli bench --hardware --disk 2>&1 || true
                echo ""
                tui_echo "${TUI_DIM}" "  Press Enter to continue..."
                read -r
            ;;
            2)
                tui_clear
                tui_echo "${TUI_DIM}" "  Network tests download data from each endpoint."
                echo ""
                tui_cli bench --network 2>&1 || true
                echo ""
                tui_echo "${TUI_DIM}" "  Press Enter to continue..."
                read -r
            ;;
            3)
                tui_clear
                tui_echo "${TUI_DIM}" "  Full benchmark running; network tests use bandwidth."
                echo ""
                tui_cli bench 2>&1 || true
                echo ""
                tui_echo "${TUI_DIM}" "  Press Enter to continue..."
                read -r
            ;;
            4 | 0)
                return
            ;;
            -1) ;;
        esac
    done
}

##
# Show about / info dialog.
##
function tui_about() {
    tui_clear
    tui_echo "${TUI_BORDER}" "═══════════════════════════════════════════════════════════"
    tui_echo "${TUI_BG}"
    printf '  %-58s\n' " LEMPer Stack — Interactive TUI"
    tui_echo "${TUI_BORDER}" "═══════════════════════════════════════════════════════════"
    echo ""
    tui_echo "${TUI_DIM}" "  Version:      ${PROG_VERSION}"
    tui_echo "${TUI_DIM}" "  Description:  Linux, Nginx, MySQL/MariaDB, PHP manager"
    tui_echo "${TUI_DIM}" "  TUI:          Pure-Bash terminal interface"
    tui_echo "${TUI_DIM}" "  Author:       MasEDI.Net (me@masedi.net)"
    echo ""
    tui_rule 60
    echo ""

    if [[ -f /etc/lemper/lemper.conf ]]; then
        tui_echo "${TUI_HIGHLIGHT}" "  Server Configuration:"
        echo ""
        # Show key config values.
        local domain
        domain=$(grep -E '^LEMPER_USERNAME=' /etc/lemper/lemper.conf 2>/dev/null | cut -d= -f2 || echo "unknown")
        printf '  %-30s %s\n' "Admin User:" "${domain}"
        local mysql_ver
        mysql_ver=$(grep -E '^MYSQL_VERSION=' /etc/lemper/lemper.conf 2>/dev/null | cut -d= -f2 || echo "unknown")
        printf '  %-30s %s\n' "MySQL/MariaDB:" "${mysql_ver}"
        local php_ver
        php_ver=$(grep -E '^DEFAULT_PHP_VERSION=' /etc/lemper/lemper.conf 2>/dev/null | cut -d= -f2 || echo "unknown")
        printf '  %-30s %s\n' "PHP Version:" "${php_ver}"
    fi

    echo ""
    tui_echo "${TUI_DIM}" "  Press Enter to return to main menu..."
    read -r
}

##
# Show TUI help.
##
function tui_help() {
    cat <<- EOL
${CMD_PARENT} ${CMD_NAME} ${PROG_VERSION}
LEMPer interactive dashboard — manage sites, databases, services, and security.

Usage: ${CMD_PARENT} ${CMD_NAME} [option]

Options:
  -h, --help             Show this help.
  -v, --version          Show the TUI version.

Without an option, launches the interactive menu. The TUI requires an
interactive terminal and root privileges.

Example:
  sudo ${CMD_PARENT} ${CMD_NAME}
EOL
}

##
# Main TUI entry point.
##
function init_lemper_tui() {
    local arg

    for arg in "$@"; do
        case "${arg}" in
            help | -h | --help)
                tui_help
                return 0
            ;;
            version | -v | --version)
                echo "${CMD_PARENT} ${CMD_NAME} version ${PROG_VERSION}"
                return 0
            ;;
            *)
                error "Unknown ${CMD_NAME} option: ${arg}"
                tui_help
                exit 1
            ;;
        esac
    done

    # Check if we're in a terminal.
    if [[ ! -t 0 ]]; then
        info "TUI mode requires an interactive terminal."
        exit 1
    fi

    local choice
    while true; do
        choice=$(tui_menu "LEMPer Stack Dashboard" "Select a category:" \
            "Site Management|Virtual hosts, domains, frameworks" \
            "Database Management|MySQL/MariaDB databases" \
            "System Status|Services, disk, memory" \
            "Security & Firewall|Fail2ban, CrowdSec, SSL, firewall" \
            "Live Logs|Stream service logs in real time" \
            "Benchmark|Hardware, disk I/O, and network speed" \
            "About|Show LEMPer version and configuration" \
            "Exit|Quit the application")

        case "${choice}" in
            1)
                tui_sites
            ;;
            2)
                tui_databases
            ;;
            3)
                tui_system_status
            ;;
            4)
                tui_security
            ;;
            5)
                tui_logs
            ;;
            6)
                tui_bench
            ;;
            7)
                tui_about
            ;;
            8 | 0)
                tui_clear
                tui_echo "${TUI_BORDER}" "Thank you for using LEMPer Stack. Goodbye!"
                exit 0
            ;;
            *) ;;  # Invalid, loop continues
        esac
    done
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_lemper_tui "$@"
