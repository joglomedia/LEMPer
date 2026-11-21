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



function lemper_monit_configure() {
    local root=/etc/lemper/monitoring config=/etc/lemper/monitoring/monitrc
    local port="${MONITOR_HTTP_PORT:-2813}" email="${MONITOR_ALERT_EMAIL:-}" smtp="${MONITOR_SMTP_HOST:-localhost}"
    [[ "$port" =~ ^[0-9]{1,5}$ ]] && ((10#$port > 1024 && 10#$port <= 65535)) || return 1
    [[ "$smtp" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
    if [[ -n "$email" ]]; then
        [[ "$email" =~ ^[A-Za-z0-9_.+-]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,63}$ ]] || { error "Invalid monitoring alert address."; return 1; }
    fi
    if [[ "${DRYRUN:-false}" == true ]]; then info "Would configure loopback-only authenticated Monit monitoring."; return 0; fi
    [[ ! -L "$root" && ! -L "$config" ]] || return 1
    install -d -m 0700 "$root" /var/lib/lemper-monit || return 1
    if [[ -e "$config" && ! -f "$root/managed" ]]; then error "Refusing to replace unmanaged monitoring configuration."; return 1; fi
    local password temporary previous="" was_active=false
    systemctl is-active --quiet lemper-monit.service && was_active=true
    if [[ -f "$root/password" ]]; then IFS= read -r password < "$root/password"; else
        password=$(openssl rand -hex 24) || return 1
        (umask 077; printf '%s\n' "$password" > "$root/password") || return 1
    fi
    [[ "$password" =~ ^[a-f0-9]{48}$ ]] || return 1
    temporary=$(mktemp "$root/.config.XXXXXXXX") || return 1
    cat > "$temporary" <<EOF_CONFIG
set daemon 60
set logfile syslog
set pidfile /run/lemper-monit.pid
set idfile /var/lib/lemper-monit/id
set statefile /var/lib/lemper-monit/state
set httpd port $port and use address 127.0.0.1
    allow admin:$password
check system lemper-system
    if loadavg (5min) > 4 for 5 cycles then alert
    if memory usage > 90% for 5 cycles then alert
check filesystem lemper-root with path /
    if space usage > 90% for 5 cycles then alert
EOF_CONFIG
    if [[ -n "$email" ]]; then printf 'set mailserver %s port 25
set alert %s
' "$smtp" "$email" >> "$temporary"; fi
    # Only probe a web listener when the managed stack has one.
    if systemctl is-active --quiet nginx; then
        printf 'check host lemper-web with address 127.0.0.1
    if failed port 80 protocol http for 3 cycles then alert
' >> "$temporary"
    fi
    chmod 0600 "$temporary" || { rm -f "$temporary"; return 1; }
    if ! monit -t -c "$temporary"; then rm -f "$temporary"; return 1; fi
    [[ ! -f "$config" ]] || { previous="$config.previous"; cp -p "$config" "$previous" || return 1; }
    touch "$root/managed" || return 1
    mv -T "$temporary" "$config" || return 1
    cat > /etc/systemd/system/lemper-monit.service <<'UNIT'
[Unit]
Description=LEMPer authenticated local monitoring
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/monit -I -c /etc/lemper/monitoring/monitrc
ExecReload=/usr/bin/monit -c /etc/lemper/monitoring/monitrc reload
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
    systemd-analyze verify /etc/systemd/system/lemper-monit.service || return 1
    lemper_exec systemctl daemon-reload || return 1
    if ! lemper_exec systemctl enable --now lemper-monit.service || ! lemper_exec systemctl restart lemper-monit.service; then
        [[ -z "$previous" ]] || mv -T "$previous" "$config"
        if [[ "$was_active" == true ]]; then systemctl restart lemper-monit.service || error "Previous monitoring service could not be restarted.";
        else systemctl disable --now lemper-monit.service >/dev/null 2>&1 || true; fi
        error "Monitoring activation failed."; return 1
    fi
    touch "$root/managed"
}
function lemper_monitor_help() {
    echo 'Usage: lemperctl monitor <status|check|reload|logs> [--dry-run]'
    echo 'HTTP status is loopback-only and authenticated; credentials stay in /etc/lemper/monitoring/.'
}
function lemper_monitor_command() {
    local action="${1:-help}" argument DRYRUN="${DRYRUN:-false}"
    [[ $# == 0 ]] || shift
    lemper_parse_args hv 'help,version,dry-run' "$@" || return 1
    for argument in "${LEMPER_PARSED_ARGS[@]}"; do
        case "$argument" in --dry-run) DRYRUN=true ;; -h|--help) action=help ;; -v|--version) action=version ;; --) ;; *) return 1 ;; esac
    done
    case "$action" in
        help|-h|--help) lemper_monitor_help ;;
        version|-v|--version) echo "${CMD_PARENT:-lemperctl} monitor version ${PROG_VERSION:-}" ;;
        status) lemper_exec monit -c /etc/lemper/monitoring/monitrc status ;;
        check) lemper_exec monit -t -c /etc/lemper/monitoring/monitrc ;;
        reload) lemper_with_lock lemper_monit_reload ;;
        logs) lemper_exec journalctl -u lemper-monit --no-pager -n 100 ;;
        *) error "Unknown monitoring command."; return 1 ;;
    esac
}
function lemper_monit_reload() {
    lemper_exec monit -t -c /etc/lemper/monitoring/monitrc || return 1
    lemper_exec systemctl reload lemper-monit.service
}
