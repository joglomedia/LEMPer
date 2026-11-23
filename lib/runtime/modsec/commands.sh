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

##
# Print help.
##
function modsec_help() {
    cat <<-EOL
${CMD_PARENT} ${CMD_NAME} ${PROG_VERSION}
LEMPer ModSecurity WAF manager — status, reporting, and CRS auto-tuning.

Usage: ${CMD_PARENT} ${CMD_NAME} <command> [options]

Commands:
  status                 Show engine mode, CRS version, and tuning values.
  report                 Summarize triggered rules from the audit log.
  tune [options]         Update CRS paranoia level and anomaly thresholds.

Tune options:
  -e, --engine <mode>    SecRuleEngine mode: On, Off, or DetectionOnly.
  -p, --paranoia <1-4>   OWASP CRS paranoia level.
  --inbound <score>      Inbound anomaly score threshold (default 5).
  --outbound <score>     Outbound anomaly score threshold (default 4).
  --auto                 Derive conservative values from the audit log.
  --apply                Write the tuning and reload Nginx (preview otherwise).
  -h, --help             Show this help.
  -v, --version          Output version information and exit.

Examples:
  ${CMD_PARENT} ${CMD_NAME} status
  ${CMD_PARENT} ${CMD_NAME} report
  ${CMD_PARENT} ${CMD_NAME} tune --auto --apply
  ${CMD_PARENT} ${CMD_NAME} tune --engine On --paranoia 2 --apply
EOL
}

##
# Main entry point.
##
function init_lemper_modsec() {
    local subcommand="${1:-status}"

    if [[ $# -gt 0 ]]; then
        shift
    fi

    case "${subcommand}" in
        status)
            modsec_status
            ;;
        report)
            modsec_report
            ;;
        tune)
            modsec_tune "$@"
            ;;
        help | -h | --help)
            modsec_help
            ;;
        version | -v | --version)
            echo "${CMD_PARENT} ${CMD_NAME} version ${PROG_VERSION}"
            ;;
        *)
            error "Unknown ${CMD_NAME} command: ${subcommand}"
            modsec_help
            return 1
            ;;
    esac
}

# shellcheck disable=SC2034 # State is shared with the named service driver.
function lemper_modsec_initialize() {
    MODSEC_CONF_DIR="${MODSEC_CONF_DIR:-/etc/modsecurity}"
    MODSEC_MAIN_CONF="${MODSEC_CONF_DIR}/modsecurity.conf"
    MODSEC_TUNING_CONF="${MODSEC_CONF_DIR}/lemper-tuning.conf"
    MODSEC_CRS_DIR="${MODSEC_CRS_DIR:-}"
    if [[ -z "${MODSEC_CRS_DIR}" || ! -d "${MODSEC_CRS_DIR}" ]]; then
        if [[ -d /etc/modsecurity/crs ]]; then
            MODSEC_CRS_DIR="/etc/modsecurity/crs"
        else
            MODSEC_CRS_DIR="/usr/share/modsecurity-crs"
        fi
    fi
}
