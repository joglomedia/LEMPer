#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - ModSecurity WAF Manager                                    |
# +-------------------------------------------------------------------------+
# | Status, audit-log reporting, and OWASP CRS auto-tuning.                  |
# |                                                                          |
# | Invoked as: lemper-cli modsec <status|report|tune> [options]            |
# +-------------------------------------------------------------------------+

# Version control.
CMD_PARENT="${PROG_NAME}"
CMD_NAME="modsec"

# Make sure only root can access and not direct access.
if [[ "$(type -t requires_root)" != "function" ]]; then
    echo "Direct access to this script is not permitted."
    exit 1
fi

MODSEC_CONF_DIR="${MODSEC_CONF_DIR:-/etc/modsecurity}"
MODSEC_MAIN_CONF="${MODSEC_CONF_DIR}/modsecurity.conf"
MODSEC_TUNING_CONF="${MODSEC_CONF_DIR}/lemper-tuning.conf"

# The repository package installs CRS under /etc/modsecurity/crs; keep the
# old clone location as a fallback for existing installs.
MODSEC_CRS_DIR="${MODSEC_CRS_DIR:-}"
if [[ -z "${MODSEC_CRS_DIR}" || ! -d "${MODSEC_CRS_DIR}" ]]; then
    if [[ -d /etc/modsecurity/crs ]]; then
        MODSEC_CRS_DIR="/etc/modsecurity/crs"
    else
        MODSEC_CRS_DIR="/usr/share/modsecurity-crs"
    fi
fi

##
# Locate the ModSecurity audit log.
##
function modsec_find_log() {
    local candidate

    for candidate in \
        "${MODSEC_AUDIT_LOG:-/var/log/modsec_audit.log}" \
        /var/log/modsecurity/modsec_audit.log \
        /var/log/nginx/error.log; do
        if [[ -f "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    return 1
}

##
# Read a plain directive value from a config file.
##
function modsec_conf_value() {
    local key="${1}"
    local file="${2}"
    local value

    value=$(awk -v k="${key}" '$1 == k { print $2; exit }' "${file}" 2>/dev/null || true)
    printf '%s\n' "${value}"
}

##
# Read a tx variable set by the LEMPer tuning file.
##
function modsec_tuning_value() {
    local variable="${1}"
    local value

    if [[ ! -f "${MODSEC_TUNING_CONF}" ]]; then
        printf '%s\n' ""
        return 0
    fi

    value=$(sed -n "s/.*setvar:tx\.${variable}=\([0-9][0-9]*\).*/\1/p" \
        "${MODSEC_TUNING_CONF}" 2>/dev/null | head -n 1 || true)
    printf '%s\n' "${value}"
}

##
# Count CRS rules available on disk.
##
function modsec_rule_count() {
    local count

    count=$(grep -h -c '^[[:space:]]*SecRule' "${MODSEC_CRS_DIR}/rules/"*.conf 2>/dev/null \
        | awk '{ total += $1 } END { print total + 0 }' || true)
    printf '%s\n' "${count:-0}"
}

##
# Print current ModSecurity status.
##
function modsec_status() {
    if [[ ! -f "${MODSEC_MAIN_CONF}" ]]; then
        error "ModSecurity is not installed. Run 'bash scripts/install_modsec.sh' first."
        exit 1
    fi

    local engine paranoia inbound outbound crs_version log_file

    engine=$(modsec_conf_value "SecRuleEngine" "${MODSEC_TUNING_CONF}")
    [[ -z "${engine}" ]] && engine=$(modsec_conf_value "SecRuleEngine" "${MODSEC_MAIN_CONF}")
    [[ -z "${engine}" ]] && engine="DetectionOnly"

    paranoia=$(modsec_tuning_value "paranoia_level")
    inbound=$(modsec_tuning_value "inbound_anomaly_score_threshold")
    outbound=$(modsec_tuning_value "outbound_anomaly_score_threshold")

    [[ -z "${paranoia}" ]] && paranoia=1
    [[ -z "${inbound}" ]] && inbound=5
    [[ -z "${outbound}" ]] && outbound=4

    crs_version="unknown"
    if [[ -f "${MODSEC_CRS_DIR}/crs-setup.conf" ]]; then
        crs_version=$(sed -n 's/^# OWASP CRS ver\.\(.*\)$/\1/p' \
            "${MODSEC_CRS_DIR}/crs-setup.conf" 2>/dev/null | head -n 1 || true)
    fi
    if [[ -z "${crs_version}" && -n $(command -v dpkg-query) ]]; then
        crs_version=$(dpkg-query -W -f='${Version}' modsecurity-crs 2>/dev/null || true)
    fi
    [[ -z "${crs_version}" ]] && crs_version="unknown"

    log_file=$(modsec_find_log 2>/dev/null || true)

    echo "ModSecurity status"
    echo "  Engine:              ${engine}"
    echo "  Paranoia level:      ${paranoia}"
    echo "  Anomaly threshold:   ${inbound} inbound / ${outbound} outbound"
    echo "  CRS version:         ${crs_version}"
    echo "  Rules available:     $(modsec_rule_count)"
    echo "  Main config:         ${MODSEC_MAIN_CONF}"
    echo "  Tuning config:       ${MODSEC_TUNING_CONF}"
    echo "  Audit log:           ${log_file:-not found}"
    echo "  Per-site include:    /etc/nginx/includes/modsec.conf"
}

##
# Summarize triggered rules from the audit log.
##
function modsec_report() {
    local log_file

    if ! log_file=$(modsec_find_log); then
        error "No ModSecurity log found. Check SecAuditLog in ${MODSEC_MAIN_CONF}."
        exit 1
    fi

    echo "ModSecurity rule report"
    echo "  Log: ${log_file}"
    echo ""

    local total inbound_blocks outbound_blocks
    total=$(grep -c '\[id "[0-9]' "${log_file}" 2>/dev/null || true)
    total=${total:-0}
    inbound_blocks=$(grep -c '\[id "949110"\]' "${log_file}" 2>/dev/null || true)
    inbound_blocks=${inbound_blocks:-0}
    outbound_blocks=$(grep -c '\[id "959100"\]' "${log_file}" 2>/dev/null || true)
    outbound_blocks=${outbound_blocks:-0}

    echo "  Triggered rule events:   ${total}"
    echo "  Inbound anomaly blocks:  ${inbound_blocks}"
    echo "  Outbound anomaly blocks: ${outbound_blocks}"
    echo ""

    if [[ "${total}" -eq 0 ]]; then
        info "No triggered rules found in the log yet."
        return 0
    fi

    echo "Top triggered rules:"
    grep -oE '\[id "[0-9]+"\]' "${log_file}" 2>/dev/null \
        | sed -E 's/[^0-9]//g' \
        | sort | uniq -c | sort -rn | head -20 \
        | awk '{ printf "  %-8s %s hits\n", $2, $1 }' || true

    echo ""
    info "Run '${CMD_PARENT} ${CMD_NAME} tune --auto --apply' to tune CRS from this data."
}

##
# Validate and normalize tuning parameters.
##
function modsec_validate_tuning() {
    local engine="${1}"
    local paranoia="${2}"
    local inbound="${3}"
    local outbound="${4}"

    if [[ ! "${engine}" =~ ^(On|Off|DetectionOnly)$ ]]; then
        fail "Invalid engine '${engine}'. Use On, Off, or DetectionOnly."
    fi

    if [[ ! "${paranoia}" =~ ^[1-4]$ ]]; then
        fail "Invalid paranoia level '${paranoia}'. Use 1-4."
    fi

    if [[ ! "${inbound}" =~ ^[0-9]+$ ]] || [[ ! "${outbound}" =~ ^[0-9]+$ ]]; then
        fail "Anomaly thresholds must be positive integers."
    fi
}

##
# Derive conservative tuning values from the audit log.
##
function modsec_auto_params() {
    local log_file blocks paranoia inbound outbound

    paranoia=1
    inbound=5
    outbound=4

    if log_file=$(modsec_find_log); then
        blocks=$(grep -c '\[id "949110"\]' "${log_file}" 2>/dev/null || true)
        blocks=${blocks:-0}

        if [[ "${blocks}" -gt 10 ]]; then
            info "Detected ${blocks} inbound anomaly blocks — using PL1 with relaxed thresholds." >&2
            paranoia=1
            inbound=10
            outbound=8
        else
            info "Low anomaly volume (${blocks} blocks) — using PL2." >&2
            paranoia=2
        fi
    else
        info "No audit log found — keeping conservative PL1." >&2
    fi

    printf '%s %s %s\n' "${paranoia}" "${inbound}" "${outbound}"
}

##
# Ensure the tuning file is included before the CRS rules.
##
function modsec_ensure_include() {
    local include_line="Include ${MODSEC_TUNING_CONF}"

    if grep -qF "${MODSEC_TUNING_CONF}" "${MODSEC_MAIN_CONF}" 2>/dev/null; then
        return 0
    fi

    if [[ "${DRYRUN}" == true ]]; then
        echo_color "${YELLOW}" -n "would add "
        echo "${include_line} to ${MODSEC_MAIN_CONF}"
        return 0
    fi

    local tmp
    tmp=$(mktemp)
    awk -v inc="${include_line}" '
        { print }
        /crs-setup\.conf/ && !inserted { print inc; inserted = 1 }
    ' "${MODSEC_MAIN_CONF}" > "${tmp}"

    if ! grep -qF "${include_line}" "${tmp}"; then
        printf '%s\n' "${include_line}" >> "${tmp}"
    fi

    run install -m 0644 "${tmp}" "${MODSEC_MAIN_CONF}"
    run rm -f "${tmp}"
}

##
# Write the LEMPer tuning configuration.
##
function modsec_write_tuning() {
    local engine="${1}"
    local paranoia="${2}"
    local inbound="${3}"
    local outbound="${4}"
    local tmp

    if [[ "${DRYRUN}" == true ]]; then
        info "Would write ${MODSEC_TUNING_CONF}:"
        echo "  SecRuleEngine ${engine}"
        echo "  paranoia_level=${paranoia} inbound=${inbound} outbound=${outbound}"
        return 0
    fi

    run mkdir -p "${MODSEC_CONF_DIR}"
    tmp=$(mktemp)

    cat > "${tmp}" <<EOL
# LEMPer ModSecurity tuning
# Generated by '${CMD_PARENT} ${CMD_NAME} tune'. Manual edits may be overwritten.
# Custom rule IDs (1000001+) avoid collisions with the CRS 900000 range.

SecRuleEngine ${engine}

SecAction "id:1000001,phase:1,nolog,pass,t:none,setvar:tx.paranoia_level=${paranoia}"
SecAction "id:1000002,phase:1,nolog,pass,t:none,setvar:tx.executing_paranoia_level=${paranoia}"
SecAction "id:1000003,phase:1,nolog,pass,t:none,setvar:tx.inbound_anomaly_score_threshold=${inbound}"
SecAction "id:1000004,phase:1,nolog,pass,t:none,setvar:tx.outbound_anomaly_score_threshold=${outbound}"
EOL

    run install -m 0644 "${tmp}" "${MODSEC_TUNING_CONF}"
    run rm -f "${tmp}"
}

##
# Tune the engine mode, paranoia level, and anomaly thresholds.
##
function modsec_tune() {
    local engine="" paranoia="" inbound="" outbound=""
    local auto=false apply=false

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -e | --engine)
                engine="${2:-}"
                shift 2
            ;;
            -p | --paranoia)
                paranoia="${2:-}"
                shift 2
            ;;
            --inbound)
                inbound="${2:-}"
                shift 2
            ;;
            --outbound)
                outbound="${2:-}"
                shift 2
            ;;
            --auto)
                auto=true
                shift
            ;;
            --apply)
                apply=true
                shift
            ;;
            -h | --help)
                modsec_help
                exit 0
            ;;
            *)
                fail "Unknown option: ${1}"
            ;;
        esac
    done

    if [[ ! -f "${MODSEC_MAIN_CONF}" ]]; then
        error "ModSecurity is not installed. Run 'bash scripts/install_modsec.sh' first."
        exit 1
    fi

    # Fill unspecified values from the current tuning or defaults.
    [[ -z "${engine}" ]] && engine=$(modsec_conf_value "SecRuleEngine" "${MODSEC_TUNING_CONF}")
    [[ -z "${engine}" ]] && engine=$(modsec_conf_value "SecRuleEngine" "${MODSEC_MAIN_CONF}")
    [[ -z "${engine}" ]] && engine="DetectionOnly"

    [[ -z "${paranoia}" ]] && paranoia=$(modsec_tuning_value "paranoia_level")
    [[ -z "${inbound}" ]] && inbound=$(modsec_tuning_value "inbound_anomaly_score_threshold")
    [[ -z "${outbound}" ]] && outbound=$(modsec_tuning_value "outbound_anomaly_score_threshold")

    if [[ "${auto}" == true ]]; then
        local auto_values
        auto_values=$(modsec_auto_params)
        read -r paranoia inbound outbound <<< "${auto_values}"
    fi

    [[ -z "${paranoia}" ]] && paranoia=1
    [[ -z "${inbound}" ]] && inbound=5
    [[ -z "${outbound}" ]] && outbound=4

    modsec_validate_tuning "${engine}" "${paranoia}" "${inbound}" "${outbound}"

    echo "Proposed ModSecurity tuning:"
    echo "  Engine:            ${engine}"
    echo "  Paranoia level:    ${paranoia}"
    echo "  Inbound threshold: ${inbound}"
    echo "  Outbound threshold: ${outbound}"

    if [[ "${apply}" != true ]]; then
        echo ""
        info "Preview only. Re-run with --apply to write the tuning and reload Nginx."
        return 0
    fi

    local backup=""
    if [[ -f "${MODSEC_TUNING_CONF}" ]]; then
        backup=$(mktemp)
        cp "${MODSEC_TUNING_CONF}" "${backup}"
    fi

    modsec_write_tuning "${engine}" "${paranoia}" "${inbound}" "${outbound}"
    modsec_ensure_include

    if [[ "${DRYRUN}" == true ]]; then
        info "Tuning applied in dry run mode."
        return 0
    fi

    if command -v nginx >/dev/null 2>&1 && ! nginx -t >/dev/null 2>&1; then
        error "Nginx configuration test failed — rolling back ModSecurity tuning."

        if [[ -n "${backup}" ]]; then
            install -m 0644 "${backup}" "${MODSEC_TUNING_CONF}"
        else
            rm -f "${MODSEC_TUNING_CONF}"
        fi

        [[ -n "${backup}" ]] && rm -f "${backup}"
        exit 1
    fi

    if command -v systemctl >/dev/null 2>&1; then
        run systemctl reload nginx
    fi

    [[ -n "${backup}" ]] && rm -f "${backup}"
    success "ModSecurity tuning applied and Nginx reloaded."
}

##
# Print help.
##
function modsec_help() {
    cat <<- EOL
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
            exit 1
        ;;
    esac
}

init_lemper_modsec "$@"
