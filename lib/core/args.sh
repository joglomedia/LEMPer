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



# Normalize options as an array, without evaluating shell code.
# SHORT uses getopt's a:b form; LONG is a comma-separated list with ':' for values.
function lemper_parse_args() {
    local short="${1}" long="${2}" token name spec value chars option positional=false
    shift 2
    LEMPER_PARSED_ARGS=()
    local operands=() specs=()
    IFS=',' read -r -a specs <<< "${long}"
    while [[ $# -gt 0 ]]; do
        token="${1}"; shift
        if [[ "${positional}" == true ]]; then
            operands+=("${token}")
        elif [[ "${token}" == -- ]]; then
            positional=true
        elif [[ "${token}" == --* ]]; then
            name="${token#--}"; name="${name%%=*}"; spec=""
            for option in "${specs[@]}"; do
                [[ "${option%:}" == "${name}" ]] && { spec="${option}"; break; }
            done
            [[ -n "${spec}" ]] || { error "Unknown ${CMD_NAME:-CLI} option: --${name}"; return 1; }
            if [[ "${spec}" == *: ]]; then
                if [[ "${token}" == *=* ]]; then
                    value="${token#*=}"
                else
                    [[ $# -gt 0 && "${1}" != --* ]] || { error "Missing value for --${name}"; return 1; }
                    value="${1}"; shift
                fi
                [[ -n "${value}" ]] || { error "Missing value for --${name}"; return 1; }
                LEMPER_PARSED_ARGS+=("--${name}" "${value}")
            else
                [[ "${token}" != *=* ]] || { error "--${name} takes no value."; return 1; }
                LEMPER_PARSED_ARGS+=("--${name}")
            fi
        elif [[ "${token}" == -?* ]]; then
            chars="${token#-}"
            while [[ -n "${chars}" ]]; do
                option="${chars:0:1}"; chars="${chars:1}"
                [[ "${short}" == *"${option}"* && "${option}" != : ]] ||
                    { error "Unknown ${CMD_NAME:-CLI} option: -${option}"; return 1; }
                spec="${short#*"${option}"}"
                if [[ "${spec}" == :* ]]; then
                    if [[ -n "${chars}" ]]; then
                        value="${chars}"; chars=""
                    else
                        [[ $# -gt 0 ]] || { error "Missing value for -${option}"; return 1; }
                        value="${1}"; shift
                    fi
                    [[ -n "${value}" ]] || { error "Missing value for -${option}"; return 1; }
                    LEMPER_PARSED_ARGS+=("-${option}" "${value}")
                else
                    LEMPER_PARSED_ARGS+=("-${option}")
                fi
            done
        else
            operands+=("${token}")
        fi
    done
    LEMPER_PARSED_ARGS+=(-- "${operands[@]}")
}
