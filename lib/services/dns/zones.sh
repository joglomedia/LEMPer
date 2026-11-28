#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | Authoritative DNS Zone Publication                                      |
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

# Compile in a chroot containing only the input. Includes cannot read host files.
# The caller owns the private temporary directory and supplies its lifetime.
function lemper_dns_compile() {
    local domain="$1" source="$2" work="$3"
    [[ -f "$source" && ! -L "$source" && -r "$source" ]] || { error "Expected a readable regular zone file."; return 1; }
    command -v named-compilezone >/dev/null || { error "Install bind9-utils to validate and plan zones."; return 1; }
    mkdir -m0700 "$work/input" && install -m0600 -- "$source" "$work/input/master" || return 1
    named-compilezone -q -t "$work/input" -i local -s full -F text -o - "$domain" /master >"$work/zone" || {
        error "Invalid or incomplete zone file."; return 1;
    }
    awk '$4 ~ /^(RRSIG|DNSKEY|NSEC|NSEC3|NSEC3PARAM|CDS|CDNSKEY)$/ { exit 1 }' "$work/zone" ||
        { error "Signed zone data requires a DNSSEC migration."; return 1; }
}

function lemper_dns_plan() (
    local domain="$1" file="$2" work dir="/etc/knot/lemper/zones/$1" rc
    work=$(mktemp -d) || return 1
    trap 'rm -rf -- "$work"' EXIT
    lemper_dns_compile "$domain" "$file" "$work" || return 1
    if [[ -f "$dir/committed" ]]; then
        diff -u --label published --label proposed "$dir/$(<"$dir/committed").zone" "$work/zone" && return 0
        rc=$?
        [[ "$rc" == 1 ]]
    else
        cat "$work/zone"
    fi
)

function lemper_dns_enroll() {
    local dir="/etc/knot/lemper/zones/$1" owner="$2" tmp
    core_is_valid_username "$owner" || { error "Use a short lowercase hosting account ID."; return 1; }
    [[ -f /etc/knot/lemper/enabled ]] || { error "Install the DNS component before enrollment."; return 1; }
    if [[ -f "$dir/owner" ]]; then
        [[ "$(<"$dir/owner")" == "$owner" ]] || { error "Zone already enrolled to a different account."; return 1; }
        if [[ -f "$dir/retired" && "${DRYRUN:-false}" != true ]]; then rm -f "$dir/retired" || return 1; fi
        return 0
    fi
    [[ "${DRYRUN:-false}" != true ]] || { info "Would enroll $1 for $owner."; return 0; }
    install -d -m0750 -o root -g knot "$dir" || return 1
    tmp=$(mktemp "$dir/.owner.XXXXXXXX") || return 1
    printf '%s\n' "$owner" > "$tmp" && mv -fT "$tmp" "$dir/owner"
}

function lemper_dns_newer() {
    local delta=$(( (10#$1 - 10#$2) & 4294967295 ))
    ((delta > 0 && delta < 2147483648))
}

# Require an authoritative NOERROR result. dig returns success for many DNS errors.
function lemper_dns_answer() {
    local domain="$1" server="$2" transport="$3" type="$4" result
    result=$(dig -r "@$server" -q "$domain." -t "$type" +norecurse +nosearch +time=3 +tries=1 \
        "$transport" +ignore +noall +comments +answer +norrcomments) || return 1
    awk -v name="$domain." -v type="$type" -v mode="${5:-value}" '
        /^;; ->>HEADER/ && /status: NOERROR,/ { ok=1 }
        /^;; flags:/ && /[ ;]aa[ ;]/ { aa=1; if (/[ ;]tc[ ;]/) truncated=1 }
        tolower($1)==name && $3=="IN" && $4==type {
            if (mode=="rrset") {
                ttl=$2
                sub(/^[^ \t]+[ \t]+[0-9]+[ \t]+IN[ \t]+[^ \t]+[ \t]+/, "")
                print ttl, $0
            } else if (type=="SOA") print $7; else print $5
            seen++
        }
        END { if (ok && aa && truncated) exit 2; if (!(ok && aa && seen)) exit 1 }
    ' <<<"$result"
}

function lemper_dns_check_records() {
    local domain="$1" server="$2" transport="$3" work="$4" name type
    while read -r name type; do
        lemper_dns_answer "${name%.}" "$server" "$transport" "$type" rrset > "$work/actual" || {
            # Large RRsets legitimately truncate on UDP. The next pass verifies them over TCP.
            if [[ $? == 2 && "$transport" == +notcp ]]; then
                printf 'Truncated UDP %s answer for %s on %s. Checking it over TCP.\n' "$type" "$name" "$server"
                continue
            fi
            error "Missing authoritative $type answer for $name on $server ($transport)."; return 1
        }
        awk -v name="$name" -v type="$type" 'tolower($1)==name && $4==type {
            ttl=$2
            sub(/^[^ \t]+[ \t]+[0-9]+[ \t]+IN[ \t]+[^ \t]+[ \t]+/, "")
            print ttl, $0
        }' "$work/zone" > "$work/expected" || return 1
        LC_ALL=C sort -o "$work/expected" "$work/expected" && LC_ALL=C sort -o "$work/actual" "$work/actual" || return 1
        if ! cmp -s "$work/expected" "$work/actual"; then error "$type differs for $name on $server ($transport)."; return 1; fi
    done < "$work/queries"
    printf 'Verified authoritative record sets for %s on %s (%s).\n' "$domain" "$server" "$transport"
}

function lemper_dns_check() (
    local domain="$1" expected="$2" ipv4="$3" file="$4" server transport serial answer first="" names work rc=0
    shift 4
    local servers=("$@")
    command -v dig >/dev/null || { error "Install dnsutils to verify authoritative answers."; return 1; }
    if [[ -n "$file" ]]; then
        work=$(mktemp -d) || return 1
        trap 'rm -rf -- "$work"' EXIT
        lemper_dns_compile "$domain" "$file" "$work" || return 1
        # Delegations and their glue are referrals, not authoritative answer sets.
        awk -v apex="$domain." 'NR==FNR {if ($4=="NS" && tolower($1)!=apex) cuts[tolower($1)]=1; next}
            { name=tolower($1); parent=name
              while (parent!=apex && parent!="") {
                  if (parent in cuts && !(parent==name && $4=="DS")) next
                  sub(/^[^.]*[.]/, "", parent)
              }
              if (!seen[name,$4]++) print name,$4
            }' "$work/zone" "$work/zone" > "$work/queries" || return 1
    fi
    if [[ ${#servers[@]} -eq 0 ]]; then
        names=$(dig -r +short +time=3 +tries=1 "$domain." NS) || return 1
        while IFS= read -r server; do [[ -z "$server" ]] || servers+=("${server%.}"); done <<< "$names"
    fi
    ((${#servers[@]})) || { error "No nameservers discovered. Supply a server for a private zone."; return 1; }
    for server in "${servers[@]}"; do
        core_is_valid_ipv4 "$server" || core_is_valid_ipv6 "$server" || core_is_valid_fqdn "$server" true ||
            { error "Invalid DNS server."; return 1; }
        for transport in +notcp +tcp; do
            serial=$(lemper_dns_answer "$domain" "$server" "$transport" SOA) && [[ "$serial" =~ ^[0-9]{1,10}$ ]] || {
                error "No authoritative SOA from $server ($transport)."; rc=1; continue;
            }
            [[ -n "$first" ]] || first="$serial"
            printf '%s %s %s SOA %s\n' "$server" "$transport" "$domain" "$serial"
            [[ "$serial" == "${expected:-$first}" ]] || rc=1
            if [[ -n "$ipv4" ]]; then
                if ! answer=$(lemper_dns_answer "$domain" "$server" "$transport" A) || ! grep -Fxq -- "$ipv4" <<<"$answer"; then
                    error "Expected A record absent on $server ($transport)."; rc=1
                fi
            fi
            if [[ -n "$file" ]]; then lemper_dns_check_records "$domain" "$server" "$transport" "$work" || rc=1; fi
        done
    done
    return "$rc"
)

function lemper_dns_write_ref() {
    local target="$1" value="$2" tmp
    tmp=$(mktemp "$target.XXXXXXXX") || return 1
    printf '%s\n' "$value" >"$tmp" && mv -fT "$tmp" "$target"
}

# A pending revision survives process interruption. Repeat the same apply to finish
# activating it. committed and previous advance only after the primary answers.
function lemper_dns_apply() (
    local domain="$1" file="$2" base="$3" root=/etc/knot/lemper dir="/etc/knot/lemper/zones/$1"
    local candidate serial live="" committed="" pending="" work current last temporary
    [[ -f "$root/enabled" && -f "$dir/owner" ]] || { error "Enroll this zone first."; return 1; }
    work=$(mktemp -d) || return 1
    trap 'rm -rf -- "$work"' EXIT
    lemper_dns_compile "$domain" "$file" "$work" || return 1
    kzonecheck -o "$domain" "$work/zone" >/dev/null || { error "Knot rejected the zone."; return 1; }
    candidate=$(sha256sum "$work/zone") || return 1
    candidate=${candidate%% *}
    serial=$(awk '$4=="SOA" {print $7}' "$work/zone")
    [[ "$serial" =~ ^[0-9]{1,10}$ ]] || return 1
    if [[ -f "$dir/committed" ]]; then committed=$(<"$dir/committed"); fi
    if [[ -f "$dir/pending" ]]; then pending=$(<"$dir/pending"); fi
    [[ -z "$pending" || "$pending" == "$candidate" || "${4:-}" == recovery ]] ||
        { error "Resume or roll back the pending revision before another edit."; return 1; }
    [[ -z "$base" || "$base" == "${committed:-new}" || "$candidate" == "$committed" ]] ||
        { error "Zone changed since preview."; return 1; }
    [[ ! -e "$dir/retired" ]] || { error "Zone is retired. Re-enroll it before publication."; return 1; }
    if [[ -n "$committed" && "$committed" != "$candidate" ]]; then
        [[ -n "$base" || "$pending" == "$candidate" ]] || { error "Supply --base with the last reviewed revision."; return 1; }
        last=$(awk '$4=="SOA" {print $7}' "$dir/$committed.zone") || return 1
        lemper_dns_newer "$serial" "$last" || { error "Increase the SOA serial before publication."; return 1; }
    fi
    current=$(awk '$1=="listen:" {sub(/@53$/,"",$2); print $2}' "$root/knot.conf") || return 1
    if live=$(lemper_dns_answer "$domain" "$current" +tcp SOA); then
        [[ "$live" =~ ^[0-9]{1,10}$ ]] || return 1
        if [[ "$live" == "$serial" ]]; then
            [[ "$candidate" == "$pending" || "$candidate" == "$committed" ]] || { error "Serial already served."; return 1; }
        else
            lemper_dns_newer "$serial" "$live" || { error "Proposed serial precedes the served revision."; return 1; }
        fi
    elif [[ -n "$committed" && -z "$pending" && -f "$root/published/$domain.conf" ]]; then
        error "Cannot verify the current primary SOA."; return 1
    fi
    if [[ "${DRYRUN:-false}" == true ]]; then info "Would publish $domain serial $serial revision $candidate."; return 0; fi
    if [[ "$candidate" == "$committed" && -z "$pending" && "$live" == "$serial" ]]; then
        lemper_dns_check "$domain" "$serial" "" "$work/zone" "$current" || return 1
        echo "Already published $domain serial $serial revision $candidate."; return 0
    fi
    # The daemon only reads the staged canonical file. Input paths never enter its configuration.
    if [[ ! -f "$dir/$candidate.zone" ]]; then
        temporary=$(mktemp "$dir/.revision.XXXXXXXX") || return 1
        install -o root -g knot -m0640 "$work/zone" "$temporary" && mv -fT "$temporary" "$dir/$candidate.zone" || return 1
    fi
    lemper_dns_write_ref "$dir/pending" "$candidate" || return 1
    temporary=$(mktemp "$root/published/.zone.XXXXXXXX") || return 1
    printf 'zone:\n  - domain: %s\n    file: "%s/%s.zone"\n' "$domain" "$dir" "$candidate" >"$temporary" &&
        chgrp knot "$temporary" && chmod 0640 "$temporary" && mv -fT "$temporary" "$root/published/$domain.conf" || return 1
    if ! lemper_exec knotc -c "$root/knot.conf" -b reload || ! lemper_dns_check "$domain" "$serial" "" "$work/zone" "$current"; then
        error "Publication pending. Repair the service and retry the same revision."; return 1
    fi
    if [[ -n "$committed" && "$committed" != "$candidate" ]]; then
        lemper_dns_write_ref "$dir/previous" "$committed" || return 1
    fi
    lemper_dns_write_ref "$dir/committed" "$candidate" && rm -f -- "$dir/pending" || return 1
    printf 'Published %s serial %s revision %s. Check the secondaries separately.\n' "$domain" "$serial" "$candidate"
)

function lemper_dns_rollback() (
    local domain="$1" dir="/etc/knot/lemper/zones/$1" current previous serial work
    [[ -f "$dir/committed" ]] || { error "No committed revision to restore."; return 1; }
    current=$(<"$dir/committed")
    local baseline="$current"
    if [[ -f "$dir/pending" && "$(<"$dir/pending")" != "$current" ]]; then
        previous="$current"; baseline=$(<"$dir/pending")
    elif [[ -f "$dir/previous" ]]; then previous=$(<"$dir/previous")
    else error "No previous revision."; return 1; fi
    serial=$(awk '$4=="SOA" {print $7}' "$dir/$baseline.zone") || return 1
    work=$(mktemp) || return 1
    trap 'rm -f -- "$work"' EXIT
    awk -v nextserial="$(( (10#$serial + 1) & 4294967295 ))" '$4=="SOA" {$7=nextserial} {print}' \
        "$dir/$previous.zone" >"$work" || return 1
    lemper_dns_apply "$domain" "$work" "$current" recovery
)

function lemper_dns_resume() {
    local dir="/etc/knot/lemper/zones/$1"
    [[ -f "$dir/pending" ]] || { error "No pending publication."; return 1; }
    lemper_dns_apply "$1" "$dir/$(<"$dir/pending").zone" ""
}

# Keep customer ownership and revision history after the delegation has moved.
function lemper_dns_retire() {
    local root=/etc/knot/lemper dir="/etc/knot/lemper/zones/$1"
    [[ -f "$dir/committed" && "$(<"$dir/committed")" == "$2" && ! -e "$dir/pending" ]] ||
        { error "Expected the current revision and no pending publication."; return 1; }
    [[ "${DRYRUN:-false}" != true ]] || { info "Would stop publishing $1."; return 0; }
    touch "$dir/retired" && rm -f -- "$root/published/$1.conf" && lemper_exec knotc -c "$root/knot.conf" -b reload
}
