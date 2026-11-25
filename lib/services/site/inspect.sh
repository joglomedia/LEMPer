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

# Public diagnostics only: configuration is never sourced and keys are not read.
function lemper_site_inspect_redact() {
    LC_ALL=C awk '
        {
            lower=tolower($0)
            route=(lower ~ /^[[:space:]]*(fastcgi|proxy|uwsgi|scgi|grpc)_pass[[:space:]]/)
            secret=(lower ~ /password|(^|[_[:space:][:punct:]])pass($|[_[:space:][:punct:]])|secret|token|authorization|credential|api[_-]?key/)
            if ((!route && secret) || lower ~ /^[[:space:]]*env\[/ || lower ~ /:\/\/[^/[:space:]:@]+:[^/[:space:]@]+@/) print "# [REDACTED]"
            else print
        }
    ' "$1"
}
function lemper_site_inspect_flat() {
    local path="$1" marker="$2" domain="$3" allowed="$4" line key value result='{}'
    [[ -f "$path" ]] || {
        printf 'null\n'
        return
    }
    [[ ! -L "$path" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        [[ "$line" =~ ^[[:space:]]*([A-Z_]+)[[:space:]]*=(.*)$ ]] || return 1
        key="${BASH_REMATCH[1]}" value="${BASH_REMATCH[2]}"
        if [[ "$value" == \"* || "$value" == \'* ]]; then
            [[ ${#value} -ge 2 && "${value: -1}" == "${value:0:1}" ]] || return 1
            value="${value:1:${#value}-2}"
        fi
        [[ "|$allowed|" == *"|$key|"* ]] || continue
        result=$(jq -nc --argjson data "$result" --arg key "${key,,}" --arg value "$value" '$data + {($key):$value}') || return 1
    done <"$path"
    jq -e --arg marker "$marker" --arg domain "$domain" '.owner_marker == $marker and .domain == $domain' <<<"$result" >/dev/null || return 1
    printf '%s\n' "$result"
}
function lemper_site_inspect_legacy() {
    local path="$1" line section="" key value result='{}' allowed='app_uid|app_framework|app_db_user|app_db_name|app_admin_user|app_admin_email|app_webroot|app_db_pass|app_admin_pass'
    local -A sections=() fields=()
    [[ -f "$path" ]] || {
        printf 'null\n'
        return
    }
    [[ ! -L "$path" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -n "$line" && "$line" != \#* && "$line" != \;* ]] || continue
        if [[ "$line" =~ ^\[([^]]+)\][[:space:]]*$ ]]; then
            section="${BASH_REMATCH[1]}"
            [[ -z "${sections[$section]:-}" ]] || return 1
            sections["$section"]=1
            result=$(jq -nc --argjson data "$result" --arg section "$section" '$data + {($section):{}}') || return 1
            continue
        fi
        [[ -n "$section" && "$line" =~ ^([^=:[:space:]]+)[[:space:]]*[=:][[:space:]]*(.*)$ ]] || return 1
        key="${BASH_REMATCH[1],,}" value="${BASH_REMATCH[2]}"
        [[ -z "${fields["$section:$key"]:-}" ]] || return 1
        fields["$section:$key"]=1
        [[ "|$allowed|" == *"|$key|"* ]] || continue
        value="${value#\"}" value="${value#\'}" value="${value%\"}" value="${value%\'}"
        [[ "$key" != app_db_pass && "$key" != app_admin_pass ]] || value='[REDACTED]'
        result=$(jq -nc --argjson data "$result" --arg section "$section" --arg key "$key" --arg value "$value" '$data | .[$section][$key]=$value') || return 1
    done <"$path"
    printf '%s\n' "$result"
}
function lemper_site_inspect_certificate() {
    local root="$1" configured="$2" domain="$3" path result type=configured details line key value names='[]' expires now remaining matches=false
    if [[ "$configured" != /* || "$configured" == *'$'* ]]; then
        jq -nc --arg path "$configured" '{cert_path:$path,status:"unresolved"}'
        return
    fi
    path="$root/${configured#/}"
    case "$configured" in /etc/letsencrypt/*) type=letsencrypt ;; /etc/lemper/ssl/*) type=self-signed ;; esac
    result=$(jq -nc --arg path "$configured" --arg type "$type" '{cert_path:$path,type:$type}') || return 1
    if [[ ! -f "$path" ]]; then
        jq -nc --argjson data "$result" '$data + {status:"missing"}'
        return
    fi
    if ! details=$(openssl x509 -in "$path" -noout -subject -issuer -dates -fingerprint -sha256 -ext subjectAltName 2>/dev/null); then
        jq -nc --argjson data "$result" '$data + {status:"invalid"}'
        return
    fi
    while IFS= read -r line; do
        key=""
        case "$line" in
            subject=*) key=subject ;;
            issuer=*) key=issuer ;;
            notBefore=*) key=not_before ;;
            notAfter=*) key=not_after ;;
            'sha256 Fingerprint='*) key=sha256_fingerprint ;;
        esac
        if [[ -n "$key" ]]; then
            value="${line#*=}"
            result=$(jq -nc --argjson data "$result" --arg key "$key" --arg value "$value" '$data + {($key):$value}') || return 1
        fi
        while [[ "$line" =~ DNS:([^,[:space:]]+) ]]; do
            value="${BASH_REMATCH[1]}"
            names=$(jq -nc --argjson data "$names" --arg value "$value" '$data + [$value]') || return 1
            line="${line#*"DNS:$value"}"
        done
    done <<<"$details"
    openssl x509 -in "$path" -noout -checkhost "$domain" >/dev/null 2>&1 && matches=true
    result=$(jq -nc --argjson data "$result" --argjson names "$names" --argjson matches "$matches" '$data + {status:"readable",dns_names:$names,hostname_matches:$matches}') || return 1
    value=$(jq -r '.not_after // empty' <<<"$result")
    if [[ -n "$value" ]]; then
        expires=$(date -u -d "$value" +%s) && now=$(date -u +%s) || return 1
        remaining=$((expires - now))
        # Floor toward negative infinity, matching expired certificate semantics.
        result=$(jq -nc --argjson data "$result" --argjson seconds "$remaining" '$data + {days_remaining:($seconds/86400|floor),expired:($seconds<=0)}') || return 1
    fi
    printf '%s\n' "$result"
}
function lemper_site_inspect() (
    local domain="$1" section="$2" root="${LEMPER_SITE_INSPECT_ROOT:-/}" vhost enabled=false nginx=null fpm=null legacy=null site=null apps='[]' ssl=null text content php="" framework="" user="" socket="" pool listen file app cert certs='[]' result view value
    [[ "$root" == /* && "$domain" =~ ^[A-Za-z0-9.-]+$ && ${#domain} -le 253 ]] || return 1
    case "$section" in config | fpm | app | ssl | all | json) ;; *) return 1 ;; esac
    vhost="$root/etc/nginx/sites-available/$domain.conf"
    [[ ! -L "$root/etc/nginx/sites-enabled/$domain.conf" || ! -e "$root/etc/nginx/sites-enabled/$domain.conf" ]] || enabled=true
    if [[ -s "$vhost" ]]; then
        text=$(cat "$vhost") && content=$(lemper_site_inspect_redact "$vhost") || return 1
        [[ ! "$text" =~ fastcgi_pass[^\;]*php([0-9]+\.[0-9]+)-fpm ]] || php="${BASH_REMATCH[1]}"
        [[ ! "$text" =~ include[^\;]*vhost/site_([^.]+)\.conf ]] || framework="${BASH_REMATCH[1]}"
        [[ ! "$text" =~ fastcgi_pass[^\;]*fpm\.([a-zA-Z0-9_-]+)\.sock ]] || user="${BASH_REMATCH[1]}"
        nginx=$(jq -nc --arg content "$content"$'\n' --arg php "$php" --arg framework "$framework" --arg user "$user" \
            '{content:$content,php_version:$php,framework:$framework,fpm_user:$user}') || return 1
        if [[ "$section" == fpm || "$section" == all || "$section" == json ]]; then
            [[ ! "$text" =~ fastcgi_pass[[:space:]]+(unix:)?([^\;[:space:]]+) ]] || socket="${BASH_REMATCH[2]}"
            socket="${socket/#\/var\/run\//\/run\/}"
            if [[ -n "$socket" && "$socket" != *'$'* ]]; then
                for pool in "$root"/etc/php/*/fpm/pool.d/*.conf; do
                    [[ -f "$pool" && ! -L "$pool" ]] || continue
                    listen=$(sed -nE 's/^[[:space:]]*listen[[:space:]]*=[[:space:]]*([^;]+).*/\1/p' "$pool" | head -n1)
                    listen="${listen%"${listen##*[![:space:]]}"}"
                    [[ "${listen/#\/var\/run\//\/run\/}" == "$socket" ]] || continue
                    content=$(lemper_site_inspect_redact "$pool") || return 1
                    fpm=$(jq -nc --arg file "$pool" --arg content "$content"$'\n' --arg listen "$socket" '{file:$file,content:$content,listen:$listen}') || return 1
                    break
                done
            fi
        fi
    fi
    if [[ "$section" == app || "$section" == all || "$section" == json ]]; then
        legacy=$(lemper_site_inspect_legacy "$root/etc/lemper/vhost.d/$domain.conf") || return 1
        site=$(lemper_site_inspect_flat "$root/etc/lemper/sites/$domain.conf" lemper-site-v1 "$domain" 'OWNER_MARKER|DOMAIN|OWNER|WEBROOT|RUNTIME|DATABASE') || return 1
        if [[ -d "$root/etc/lemper/site-apps/$domain" ]]; then
            while IFS= read -r -d '' file; do
                app=$(lemper_site_inspect_flat "$file" lemper-app-v1 "$domain" 'OWNER_MARKER|DOMAIN|MOUNT|TYPE|OWNER|WEBROOT|PUBLIC_ROOT|RUNTIME') || return 1
                apps=$(jq -nc --argjson data "$apps" --argjson app "$app" '$data + [$app]') || return 1
            done < <(find "$root/etc/lemper/site-apps/$domain" -name '*.conf' -print0 | sort -z)
        fi
    fi
    if [[ "$section" == ssl || "$section" == all || "$section" == json ]]; then
        if [[ -f "$vhost" ]]; then
            while IFS= read -r cert; do
                [[ -n "$cert" ]] || continue
                cert=$(lemper_site_inspect_certificate "$root" "$cert" "$domain") || return 1
                certs=$(jq -nc --argjson data "$certs" --argjson cert "$cert" '$data + [$cert]') || return 1
            done < <(sed -nE "s/^[[:space:]]*ssl_certificate[[:space:]]+[\"']?([^;\"']+)[\"']?[[:space:]]*;.*/\1/p" "$vhost" | sed 's/[[:space:]]*$//')
        fi
        value=false
        [[ "$certs" == '[]' ]] || value=true
        if [[ "$certs" == '[]' ]]; then
            for cert in "/etc/letsencrypt/live/$domain/fullchain.pem" "/etc/lemper/ssl/$domain/cert.pem"; do
                [[ -f "$root/$cert" ]] || continue
                cert=$(lemper_site_inspect_certificate "$root" "$cert" "$domain") || return 1
                certs=$(jq -nc --argjson data "$certs" --argjson cert "$cert" '$data + [$cert]') || return 1
            done
        fi
        [[ "$certs" == '[]' ]] || ssl=$(jq -nc --argjson certs "$certs" --argjson enabled "$value" '$certs[0] + {enabled:$enabled,certificates:$certs}') || return 1
    fi
    [[ "$section" != config && "$section" != fpm && "$section" != all || "$nginx" != null ]] || return 1
    result=$(jq -nc --arg domain "$domain" --arg vhost "$vhost" --argjson enabled "$enabled" --argjson nginx "$nginx" \
        --argjson fpm "$fpm" --argjson legacy "$legacy" --argjson site "$site" --argjson apps "$apps" --argjson ssl "$ssl" \
        '{domain:$domain,vhost_file:$vhost,enabled:$enabled,nginx_config:$nginx,fpm_pool:$fpm,app_metadata:$legacy,site_metadata:$site,apps:$apps,ssl:$ssl}') || return 1
    if [[ "$section" == json ]]; then
        printf '%s\n' "$result"
        return
    fi
    printf 'Domain: %s\nEnabled: %s\n' "$domain" "$([[ "$enabled" == true ]] && echo Yes || echo No)"
    local views=("$section")
    [[ "$section" != all ]] || views=(config fpm app ssl)
    for view in "${views[@]}"; do
        printf '\n%s:\n' "${view^^}"
        case "$view" in config) value="$nginx" ;; fpm) value="$fpm" ;; ssl) value="$ssl" ;;
        app) value=$(jq -nc --argjson legacy "$legacy" --argjson site "$site" --argjson apps "$apps" '{legacy:$legacy,site:$site,apps:$apps}') ;;
        esac
        jq -r 'if type=="object" and has("content") then .content else . end' <<<"$value" || return 1
    done
) 2>/dev/null
