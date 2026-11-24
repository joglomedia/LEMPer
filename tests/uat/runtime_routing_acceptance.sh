#!/usr/bin/env bash
# Real default-PHP and Laravel routing checks in a designated disposable container.
set -euo pipefail
[[ $(id -u) == 0 && -f /run/.containerenv && -f /run/lemper-runtime-uat-authorized &&
$(cat /proc/1/comm) == systemd ]] || {
    echo 'Designated disposable runtime UAT container required.' >&2
    exit 2
}
[[ $(findmnt -no OPTIONS /source) == ro,* ]] || exit 2
for command in nginx php8.3 php8.4 php-fpm8.3 php-fpm8.4; do command -v "$command" >/dev/null; done
[[ -f /home/lemper/laravel-real/vendor/autoload.php ]] || {
    echo 'Prepare Laravel and supported PHP packages first.' >&2
    exit 2
}
logs=/var/log/lemper-runtime-uat
install -d -m 0700 "$logs" /checkout
cp -a /source/bin /source/lib /source/scripts /source/etc /source/share /checkout/
cp /source/.env.dist /checkout/.env
chmod 0600 /checkout/.env
cp /source/tests/uat/helpers.bash /run/runtime-helpers.bash
# shellcheck source=tests/uat/helpers.bash
. /run/runtime-helpers.bash
while IFS='|' read -r key value; do uat_profile_set /checkout/.env "$key" "$value"; done <<'PROFILE'
DEFAULT_PHP_VERSION|"8.3"
LEMPER_USERNAME|"lemper"
LEMPER_PASSWORD|"synthetic-profile-secret"
ENVIRONMENT|"development"
SERVER_HOSTNAME|"issues-uat.test"
SERVER_IP|"127.0.0.1"
PHP_FPM_MAX_CHILDREN|2
OPCACHE_MEMORY_MB|64
SSH_PASSWORDLESS|false
INSTALL_MAILER|false
INSTALL_SPFDKIM|false
ENCRYPT_CONFIG_AT_REST|true
PROFILE
# Real Laravel routes test Request base URL/path; PHP here is application data.
cat >/home/lemper/laravel-real/routes/web.php <<'PHP'
<?php
use Illuminate\Support\Facades\Route;
use Illuminate\Http\Request;
Route::match(['GET', 'POST'], '/probe/{path?}', function (Request $request) {
    return response()->json(['app' => 'laravel-real', 'version' => app()->version(),
      'php' => PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION, 'base' => $request->getBaseUrl(),
      'path' => $request->getPathInfo(), 'uri' => $request->getRequestUri(),
      'method' => $request->method(), 'query' => $request->query('x'), 'body' => $request->input('value')]);
})->where('path', '.*')->withoutMiddleware([\Illuminate\Foundation\Http\Middleware\PreventRequestForgery::class,
  \Illuminate\Foundation\Http\Middleware\ValidateCsrfToken::class,
  \Illuminate\Foundation\Http\Middleware\VerifyCsrfToken::class]);
PHP
for setting in APP_DEBUG=false SESSION_DRIVER=file CACHE_STORE=file QUEUE_CONNECTION=sync; do
    uat_profile_set /home/lemper/laravel-real/.env "${setting%%=*}" "${setting#*=}"
done
mkdir -p /home/lemper/laravel-real/public/uploads /home/lemper/laravel-real/public/assets
for name in evil.php evil.php84 evil.PHP evil.phtml evil.phar uploads/evil.php; do
    printf '<?php echo "UNSAFE-PHP";' >"/home/lemper/laravel-real/public/$name"
done
printf LARAVEL-ASSET >/home/lemper/laravel-real/public/assets/fixture.txt
chown -R lemper:lemper /home/lemper/laravel-real
install -d -o lemper -g lemper -m 0755 /home/lemper/second-app/public
install -d -o lemper -g lemper -m 0755 /home/lemper/logs/nginx /home/lemper/logs/php
cat >/home/lemper/second-app/public/index.php <<'PHP'
<?php header('Content-Type: application/json'); echo json_encode(['app'=>'second', 'php'=>PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION]);
PHP
chown -R lemper:lemper /home/lemper/second-app
cp -a /source/etc/nginx/includes /source/etc/nginx/vhost /etc/nginx/
cp /source/etc/nginx/fastcgi_params /etc/nginx/fastcgi_params
install -d -m 0755 /etc/nginx/site-apps
rm -f /etc/nginx/sites-enabled/default
cat >/etc/nginx/nginx.conf <<'NGINX'
user www-data;
worker_processes 1;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;
events { worker_connections 256; }
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    log_format lp_cache '$remote_addr $request $status';
    map $https $server_https { default $https; }
    map $scheme $proto_https { default $scheme; }
    include /etc/nginx/sites-enabled/*.conf;
}
NGINX
bash -c '. /checkout/lib/core/loader.sh; . /checkout/lib/core/deployment.sh; lemper_cli_snapshot /checkout' >"$logs/cli-activation.log" 2>&1
install -m 0600 /checkout/.env /etc/lemper/lemper.conf
# Initial CLI differs from the requested PHP default; site runtimes are explicit.
update-alternatives --set php /usr/bin/php8.3 >"$logs/initial-alternative.log" 2>&1
systemctl restart nginx
cases=0
function uat_case() {
    local name="$1"
    shift
    cases=$((cases + 1))
    local result
    set +e
    (
        set -e
        "$@"
    ) >"$logs/$name.log" 2>&1
    result=$?
    set -e
    if [[ "$result" == 0 ]]; then
        printf 'PASS %s\n' "$name"
    else
        printf 'FAIL %s (log: %s)\n' "$name" "$logs/$name.log"
        grep -aE '^UAT assertion: [a-z ]+( \(HTTP [0-9]{3}\))?$' "$logs/$name.log" || true
        exit 1
    fi
}
function parent_site() {
    lemperctl site create parent-uat.test --type default --runtime php@8.3 --runtime-user lemper --webroot /home/lemper/parent
    printf '<?php header("Content-Type: application/json"); echo json_encode(["app"=>"parent","php"=>PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION]);' >/home/lemper/parent/index.php
    chown lemper:lemper /home/lemper/parent/index.php
}
function encrypt_profile() {
    openssl rand -hex 32 >/etc/lemper/.config_key
    chmod 0600 /etc/lemper/.config_key
    openssl enc -aes-256-cbc -a -salt -md sha256 -pbkdf2 -pass file:/etc/lemper/.config_key \
        -in /etc/lemper/lemper.conf -out /run/lemper-profile.enc
    install -m 0600 /run/lemper-profile.enc /etc/lemper/lemper.conf
    rm /run/lemper-profile.enc
}
function php_default() {
    local before pool_hash
    pool_hash=$(sha256sum /etc/php/8.3/fpm/pool.d/lemper.conf)
    lemperctl stack config php --default-runtime=php@8.4
    [[ $(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;') == 8.4 ]]
    [[ $(php-config --version) == 8.4.* ]]
    [[ $(sha256sum /etc/php/8.3/fpm/pool.d/lemper.conf) == "$pool_hash" ]]
    local decoded
    decoded=$(mktemp)
    openssl enc -aes-256-cbc -d -a -salt -md sha256 -pbkdf2 -pass file:/etc/lemper/.config_key \
        -in /etc/lemper/lemper.conf -out "$decoded"
    grep -qx DEFAULT_PHP_VERSION=8.4 "$decoded"
    grep -qx 'LEMPER_PASSWORD="synthetic-profile-secret"' "$decoded"
    rm "$decoded"
    before=$(sha256sum /etc/lemper/lemper.conf)
    lemperctl stack config php --default-runtime=php@8.4
    [[ $(sha256sum /etc/lemper/lemper.conf) == "$before" ]]
}
function invalid_defaults() {
    local before
    before=$(sha256sum /etc/lemper/lemper.conf)
    if lemperctl stack config php --default-runtime=php@8.0; then return 1; fi
    if lemperctl stack config php --default-runtime=php@8.5; then return 1; fi
    lemperctl stack config php --default-runtime=php@8.3 --dry-run
    [[ $(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;') == 8.4 ]]
    [[ $(sha256sum /etc/lemper/lemper.conf) == "$before" ]]
}
function full_laravel_site() {
    lemperctl site create laravel-uat.test --type laravel --runtime-user lemper --webroot /home/lemper/laravel-real
    grep -q 'php8.4-fpm' /etc/nginx/sites-available/laravel-uat.test.conf
}
function http_checks() {
    local host prefix base suffix code headers body response
    headers="$logs/http-headers" body="$logs/http-body"
    response=$(curl -fsS -H 'Host: parent-uat.test' http://127.0.0.1/)
    jq -e '.php=="8.3"' <<<"$response" >/dev/null || return 1
    for host in laravel-uat.test parent-uat.test; do
        prefix="" base=""
        [[ "$host" != parent-uat.test ]] || {
            prefix=/demo
            base=/demo
        }
        code=$(curl -sS --max-time 15 -H "Host: $host" -D "$headers" -o "$body" -w '%{http_code}' "http://127.0.0.1$prefix/probe/item?x=a%20b")
        [[ "$code" == 200 ]] && jq -e --arg base "$base" '.app=="laravel-real" and .php=="8.4" and .base==$base and .path=="/probe/item" and .query=="a b"' "$body" >/dev/null || return 1
        code=$(curl -sS --max-time 15 -H "Host: $host" -D "$headers" -o "$body" -w '%{http_code}' "http://127.0.0.1$prefix/probe/item/?x=keep%26value")
        [[ "$code" == 308 ]] && grep -Fiq "$prefix/probe/item?x=keep%26value" "$headers" || return 1
        code=$(curl -sS --max-time 15 -H "Host: $host" -d value=retained -o "$body" -w '%{http_code}' "http://127.0.0.1$prefix/probe/post/")
        [[ "$code" == 308 ]] || return 1
        code=$(curl -sS --max-time 15 -H "Host: $host" -d value=retained -o "$body" -w '%{http_code}' "http://127.0.0.1$prefix/probe/post")
        [[ "$code" == 200 ]] && jq -e '.method=="POST" and .body=="retained"' "$body" >/dev/null || return 1
        code=$(curl -sS --max-time 15 -H "Host: $host" -D "$headers" -o "$body" -w '%{http_code}' "http://127.0.0.1$prefix/probe/encoded%20value/")
        [[ "$code" == 308 ]] && grep -Fiq '%20' "$headers" || return 1
        for suffix in /.env /composer.json /evil.php /evil.php84 /evil.PHP /evil.phtml /evil.phar /uploads/evil.php /index.php/extra; do
            code=$(curl -sS --max-time 15 -H "Host: $host" -o "$body" -w '%{http_code}' "http://127.0.0.1$prefix$suffix")
            [[ "$code" == 404 ]] || return 1
        done
        code=$(curl -sS --max-time 15 -H "Host: $host" -o "$body" -w '%{http_code}' "http://127.0.0.1$prefix/assets/fixture.txt")
        [[ "$code" == 200 && "$(cat "$body")" == LARAVEL-ASSET ]] || return 1
        code=$(curl -sS --max-time 15 -H "Host: $host" -D "$headers" -o "$body" -w '%{http_code}' "http://127.0.0.1$prefix/assets/")
        [[ "$code" == 403 ]] && ! grep -qi '^Location:' "$headers" || return 1
    done
    code=$(curl -sS -H 'Host: parent-uat.test' -D "$headers" -o "$body" -w '%{http_code}' 'http://127.0.0.1/demo?x=1')
    [[ "$code" == 308 ]] && grep -Fiq '/demo/?x=1' "$headers" || return 1
    code=$(curl -sS -H 'Host: parent-uat.test' -o "$body" -w '%{http_code}' http://127.0.0.1/other/)
    [[ "$code" == 200 ]] && jq -e '.app=="second"' "$body" >/dev/null
}
function reference_guards() {
    if lemperctl site remove parent-uat.test --purge --dry-run; then return 1; fi
    bash -c '. /checkout/lib/core/loader.sh; . /checkout/lib/services/php/lifecycle.sh; if lemper_php_check_references 8.4; then exit 1; fi'
}
function mount_update_and_remove() {
    lemperctl site app update parent-uat.test --mount /other --runtime=php@8.4
    lemperctl site app list parent-uat.test
    lemperctl site app remove parent-uat.test --mount /demo --yes
    test -f /home/lemper/laravel-real/public/index.php
    test ! -f /etc/nginx/site-apps/parent-uat.test/demo.conf
    lemperctl site app remove parent-uat.test --mount /other --yes
    test -f /home/lemper/second-app/public/index.php
    nginx -t
}
function access_policy_guard() {
    local framework=/etc/nginx/vhost/site_default.conf parent=/etc/nginx/sites-available/parent-uat.test.conf backup hash
    backup=$(mktemp -d)
    cp "$framework" "$backup/framework"
    cp "$parent" "$backup/parent"
    # A sibling location's authentication must not be bypassed by a new prefix.
    sed 's/location \/ {/location \/ { auth_basic private;/' "$backup/framework" >"$framework"
    if lemperctl site app add parent-uat.test --mount /protected --webroot /home/lemper/second-app --dry-run; then
        echo 'UAT assertion: location policy unexpectedly accepted'
        return 1
    fi
    cat "$backup/framework" >"$framework"
    hash=$(printf '%s\n' 'synthetic-uat-pass' | openssl passwd -apr1 -stdin)
    printf 'uat:%s\n' "$hash" >/run/runtime-uat.htpasswd
    chown root:www-data /run/runtime-uat.htpasswd
    chmod 0640 /run/runtime-uat.htpasswd
    sed '/^    root /a\    auth_basic "UAT protected";\n    auth_basic_user_file /run/runtime-uat.htpasswd;' "$backup/parent" >"$parent"
    if ! lemperctl site app add parent-uat.test --mount /protected --webroot /home/lemper/second-app; then
        echo 'UAT assertion: server policy mount rejected'
        return 1
    fi
    local path code authfile _attempt
    # A graceful reload returns before the replacement workers accept requests.
    # Wait for activation, then verify every protected route and valid login.
    code=000
    for _attempt in {1..30}; do
        code=$(curl -sS --max-time 5 -H 'Host: parent-uat.test' -o /dev/null -w '%{http_code}' http://127.0.0.1/protected/) || true
        [[ "$code" != 401 ]] || break
        sleep 0.2
    done
    if [[ "$code" != 401 ]]; then
        printf 'UAT assertion: authentication policy did not activate (HTTP %s)\n' "$code" >&2
        return 1
    fi
    for path in /protected/ /protected/index.php; do
        code=$(curl -sS --max-time 15 -H 'Host: parent-uat.test' -o /dev/null -w '%{http_code}' "http://127.0.0.1$path")
        if [[ "$code" != 401 ]]; then
            printf 'UAT assertion: unauthenticated request accepted (HTTP %s)\n' "$code"
            return 1
        fi
    done
    authfile=$(mktemp)
    chmod 0600 "$authfile"
    printf 'user = "uat:synthetic-uat-pass"\n' >"$authfile"
    if ! curl -fsS --max-time 15 --config "$authfile" -H 'Host: parent-uat.test' http://127.0.0.1/protected/ | jq -e '.app=="second"' >/dev/null; then
        rm -f "$authfile"
        echo 'UAT assertion: authenticated access failed'
        return 1
    fi
    rm -f "$authfile"
    if ! lemperctl site app remove parent-uat.test --mount /protected --yes; then
        echo 'UAT assertion: protected mount removal failed'
        return 1
    fi
    cat "$backup/parent" >"$parent"
    systemctl reload nginx
    rm -rf "$backup"
    rm /run/runtime-uat.htpasswd
}
uat_case parent_site parent_site
uat_case encrypted_profile encrypt_profile
uat_case php_default_selection_and_persistence php_default
uat_case invalid_default_and_dry_run invalid_defaults
uat_case full_laravel_uses_new_default full_laravel_site
uat_case laravel_mount lemperctl site app add parent-uat.test --mount /demo --webroot /home/lemper/laravel-real --runtime=php@8.4
uat_case second_mount_inherits_parent lemperctl site app add parent-uat.test --mount /other --webroot /home/lemper/second-app
uat_case laravel_http_and_security http_checks
uat_case references_and_purge_guards reference_guards
uat_case mount_update_and_removal_retains_data mount_update_and_remove
uat_case access_policy_preservation access_policy_guard
printf 'Runtime/routing UAT: %s passed\n' "$cases"
