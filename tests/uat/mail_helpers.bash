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

# Native protocol clients for disposable mail UAT. Credentials stay in shell
# memory/protected files, never external process arguments or diagnostic output.
function mail_close() {
    [[ -z "${mail_in:-}" ]] || exec {mail_in}>&-
    [[ -z "${mail_out:-}" ]] || exec {mail_out}<&-
    [[ -z "${mail_pid:-}" ]] || {
        kill "$mail_pid" 2>/dev/null || true
        wait "$mail_pid" 2>/dev/null || true
    }
    mail_in="" mail_out="" mail_pid=""
}
function mail_plain() {
    mail_close
    exec {mail_in}<>"/dev/tcp/$1/$2" || return 1
    exec {mail_out}<&"$mail_in"
}
function mail_tls() {
    mail_close
    local start_options=() coproc_in coproc_out
    [[ -z "${3:-}" ]] || start_options=(-starttls "$3")
    coproc MAIL_TLS { openssl s_client -quiet -connect "mail.lemper-uat.test:$1" \
        -servername mail.lemper-uat.test -verify_hostname mail.lemper-uat.test \
        -verify_return_error -CAfile /run/mail-uat/ca.pem "${start_options[@]}" 2>/dev/null; }
    mail_pid="$MAIL_TLS_PID"
    exec {mail_in}>&"${MAIL_TLS[1]}"
    exec {mail_out}<&"${MAIL_TLS[0]}"
    # Close original descriptors so mail_close can signal EOF reliably.
    coproc_in="${MAIL_TLS[1]}" coproc_out="${MAIL_TLS[0]}"
    exec {coproc_in}>&- {coproc_out}<&-
}
function smtp_reply() {
    local line
    smtp_response="" smtp_code=""
    while IFS= read -r -t 15 line <&"$mail_out"; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^([0-9]{3})([-\ ]) ]] || return 1
        smtp_code="${BASH_REMATCH[1]}"
        smtp_response+="$line"$'\n'
        [[ "${line:3:1}" != ' ' ]] || return 0
    done
    return 1
}
function smtp_command() {
    (printf '%s\r\n' "$1" >&"$mail_in") 2>/dev/null && smtp_reply
}
function smtp_open() {
    mail_plain "$1" "$2" && smtp_reply && [[ "$smtp_code" == 220 ]] \
        && smtp_command 'EHLO mail-uat.test' && [[ "$smtp_code" == 250 ]]
}
function smtp_secure() {
    mail_tls 587 "" smtp || return 1
    smtp_command 'EHLO mail-uat.test' && [[ "$smtp_code" == 250 ]]
}
function smtp_login() {
    local account="$1" password payload
    IFS= read -r password <"$2" || return 1
    payload=$(printf '\0%s\0%s' "$account" "$password" | base64 -w0) || return 1
    smtp_command "AUTH PLAIN $payload" && [[ "$smtp_code" == 235 ]]
}
function smtp_send() {
    local sender="$1" recipient="$2" subject="$3" from="${4:-$1}"
    smtp_command "MAIL FROM:<$sender>" && [[ "$smtp_code" == 250 ]] || return 1
    smtp_command "RCPT TO:<$recipient>" && [[ "$smtp_code" == 250 ]] || return 1
    smtp_command DATA && [[ "$smtp_code" == 354 ]] || return 1
    printf 'From: %s\r\nTo: %s\r\nSubject: %s\r\n\r\nLEMPer delivery fixture\r\n.\r\n' "$from" "$recipient" "$subject" >&"$mail_in" || return 1
    smtp_reply && [[ "$smtp_code" == 250 ]]
}
function imap_command() {
    local line
    imap_response=""
    # A disabled account closes an established session. Confine SIGPIPE to
    # the writer so the negative test can observe the disconnect normally.
    (printf 'A1 %s\r\n' "$1" >&"$mail_in") 2>/dev/null || return 1
    while IFS= read -r -t 15 line <&"$mail_out"; do
        line="${line%$'\r'}"
        imap_response+="$line"$'\n'
        [[ "$line" != 'A1 '* ]] || {
            [[ "$line" == 'A1 OK '* ]]
            return
        }
    done
    return 1
}
function imap_open() {
    local port="${1:-993}" start="" line
    [[ "$port" != 143 ]] || start=imap
    mail_tls "$port" "" "$start" || return 1
    # STARTTLS protocol negotiation consumes the plaintext greeting.
    [[ -n "$start" ]] || { IFS= read -r -t 15 line <&"$mail_out" && [[ "$line" == '* OK '* ]]; }
}
function imap_login() {
    local account="$1" password
    IFS= read -r password <"$2" || return 1
    password="${password//\\/\\\\}" password="${password//\"/\\\"}"
    imap_command "LOGIN \"$account\" \"$password\""
}
function mail_wait_message() {
    local account="$1" subject="$2" signer="${3:-}" attempt ids
    for ((attempt = 0; attempt < 50; attempt++)); do
        imap_open && imap_login "$account" /run/mail-uat/password && imap_command 'SELECT INBOX' || return 1
        imap_command "UID SEARCH SUBJECT \"$subject\"" || return 1
        ids=$(sed -nE 's/^\* SEARCH[[:space:]]+([0-9 ]+).*/\1/p' <<<"$imap_response")
        if [[ -n "$ids" ]]; then
            if [[ -n "$signer" ]]; then
                imap_command "UID FETCH ${ids##* } (RFC822)" || return 1
                [[ "$imap_response" == *DKIM-Signature:* && "$imap_response" == *"d=$signer"* ]] || return 1
            fi
            mail_close
            return 0
        fi
        mail_close
        sleep .2
    done
    return 1
}
