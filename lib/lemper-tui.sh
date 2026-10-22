#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Interactive TUI (Terminal User Interface)                   |
# +-------------------------------------------------------------------------+
# | A pure-Bash, menu-driven TUI for managing the LEMPer stack.              |
# | No external dependencies — uses ANSI escape sequences + read.            |
# |                                                                          |
# | Invoked as: lemper-cli tui  or  lemper-cli --interactive                |
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

    tui_clear
    tui_echo "${TUI_BORDER}" "═══════════════════════════════════════════════════════════"
    tui_echo "${TUI_BG}"
    printf '  %-58s\n' " ${title}"
    tui_echo "${TUI_BORDER}" "═══════════════════════════════════════════════════════════"
    echo ""

    local i=1
    for opt in "${options[@]}"; do
        local label
        label="${opt%%|*}"
        local desc
        desc="${opt#*|}"
        if [[ "${label}" == "${desc}" ]]; then
            desc=""
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

    local choice
    read -rp "  Select [1-${count}] or 'q' to quit: " choice

    echo ""

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
                tui_echo "${TUI_DIM}" "  Invalid selection. Press Enter to continue..."
                read -r
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
            "Manage site|Enable/disable SSL, cache, etc." \
            "Back to main menu|Return to dashboard")

        case "${choice}" in
            1)
                echo ""
                if [[ -x "${CLI_PLUGINS_DIR}/lemper-site-list" ]]; then
                    tui_clear
                    "${CLI_PLUGINS_DIR}/lemper-site-list" --all 2>&1 || true
                else
                    tui_echo "${RED}" "  lemper-site-list plugin not found."
                fi
                echo ""
                tui_echo "${TUI_DIM}" "  Press Enter to continue..."
                read -r
            ;;
            2)
                local domain
                echo ""
                read -rp "  Enter domain name: " domain
                if [[ -n "${domain}" ]]; then
                    if [[ -x "${CLI_PLUGINS_DIR}/lemper-site-show" ]]; then
                        tui_clear
                        "${CLI_PLUGINS_DIR}/lemper-site-show" "${domain}" --all 2>&1 || true
                    else
                        tui_echo "${RED}" "  lemper-site-show plugin not found."
                    fi
                fi
                echo ""
                tui_echo "${TUI_DIM}" "  Press Enter to continue..."
                read -r
            ;;
            3)
                echo ""
                tui_echo "${TUI_DIM}" "  Launching site creation wizard..."
                echo ""
                if [[ -x "${CLI_PLUGINS_DIR}/lemper-site" ]]; then
                    "${CLI_PLUGINS_DIR}/lemper-site" create 2>&1 || true
                fi
                tui_echo "${TUI_DIM}" "  Press Enter to continue..."
                read -r
            ;;
            4)
                local domain
                echo ""
                read -rp "  Enter domain name: " domain
                if [[ -n "${domain}" ]]; then
                    if [[ -x "${CLI_PLUGINS_DIR}/lemper-site" ]]; then
                        "${CLI_PLUGINS_DIR}/lemper-site" mod 2>&1 || true
                    fi
                fi
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
                if [[ -x "${CLI_PLUGINS_DIR}/lemper-db" ]]; then
                    "${CLI_PLUGINS_DIR}/lemper-db" databases 2>&1 || true
                else
                    tui_echo "${RED}" "  lemper-db plugin not found."
                fi
                echo ""
                tui_echo "${TUI_DIM}" "  Press Enter to continue..."
                read -r
            ;;
            2)
                local dbname
                echo ""
                read -rp "  Enter database name: " dbname
                if [[ -n "${dbname}" ]]; then
                    "${CLI_PLUGINS_DIR}/lemper-db" backup --dbname="${dbname}" 2>&1 || true
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
                    "${CLI_PLUGINS_DIR}/lemper-db" restore --dbname="${dbname}" --dbfile="${dbfile}" 2>&1 || true
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
                        "${CLI_PLUGINS_DIR}/lemper-db" backup-schedule --dbname="${dbname}" --dbschedule="${schedule}" 2>&1 || true
                    else
                        "${CLI_PLUGINS_DIR}/lemper-db" backup-schedule --dbname="${dbname}" 2>&1 || true
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
# Main TUI entry point.
##
function init_lemper_tui() {
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
                tui_about
            ;;
            0)
                tui_clear
                tui_echo "${TUI_BORDER}" "Thank you for using LEMPer Stack. Goodbye!"
                exit 0
            ;;
            *) ;;  # Invalid, loop continues
        esac
    done
}

# Start running unless this is a sourced library.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_lemper_tui "$@"
fi
