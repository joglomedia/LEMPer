#!/usr/bin/env bash
# Real default-PHP and Laravel routing checks in a designated disposable container.
set -euo pipefail
[[ $(id -u) == 0 && -f /run/.containerenv && -f /run/lemper-runtime-uat-authorized &&
   $(cat /proc/1/comm) == systemd ]] || { echo 'Designated disposable runtime UAT container required.' >&2; exit 2; }
[[ $(findmnt -no OPTIONS /source) == ro,* ]] || exit 2
for command in nginx php8.3 php8.4 php-fpm8.3 php-fpm8.4; do command -v "$command" >/dev/null; done
[[ -f /home/lemper/laravel-real/vendor/autoload.php ]] || { echo 'Prepare Laravel and supported PHP packages first.' >&2; exit 2; }
logs=/var/log/lemper-runtime-uat
install -d -m 0700 "$logs" /checkout
cp -a /source/bin /source/lib /source/scripts /source/etc /source/share /checkout/
cp /source/.env.dist /checkout/.env
chmod 0600 /checkout/.env
python3 - <<'PY'
from pathlib import Path
import re
p=Path('/checkout/.env');s=p.read_text()
values={'DEFAULT_PHP_VERSION':'"8.3"','LEMPER_USERNAME':'"lemper"','LEMPER_PASSWORD':'"synthetic-profile-secret"',
        'ENVIRONMENT':'"development"','SERVER_HOSTNAME':'"issues-uat.test"','SERVER_IP':'"127.0.0.1"',
        'PHP_FPM_MAX_CHILDREN':'2','OPCACHE_MEMORY_MB':'64','SSH_PASSWORDLESS':'false','INSTALL_MAILER':'false',
        'INSTALL_SPFDKIM':'false','ENCRYPT_CONFIG_AT_REST':'true'}
for k,v in values.items():
 s,n=re.subn('^'+k+'=.*$',lambda _:k+'='+v,s,flags=re.M);assert n==1,k
p.write_text(s)
# Real Laravel routes report the Request base URL and parsed path to exercise subdirectory routing.
p=Path('/home/lemper/laravel-real/routes/web.php')
p.write_text('''<?php
use Illuminate\\Support\\Facades\\Route;
use Illuminate\\Http\\Request;
Route::match(['GET', 'POST'], '/probe/{path?}', function (Request $request) {
    return response()->json(['app' => 'laravel-real', 'version' => app()->version(),
      'php' => PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION, 'base' => $request->getBaseUrl(),
      'path' => $request->getPathInfo(), 'uri' => $request->getRequestUri(),
      'method' => $request->method(), 'query' => $request->query('x'), 'body' => $request->input('value')]);
})->where('path', '.*')->withoutMiddleware([\\Illuminate\\Foundation\\Http\\Middleware\\PreventRequestForgery::class,
  \\Illuminate\\Foundation\\Http\\Middleware\\ValidateCsrfToken::class,
  \\Illuminate\\Foundation\\Http\\Middleware\\VerifyCsrfToken::class]);
''')
p=Path('/home/lemper/laravel-real/.env');s=p.read_text()
for k,v in {'APP_DEBUG':'false','SESSION_DRIVER':'file','CACHE_STORE':'file','QUEUE_CONNECTION':'sync'}.items():
 s=re.subn('^'+k+'=.*$',lambda _:k+'='+v,s,flags=re.M)[0]
p.write_text(s)
# These public PHP files must never execute or be served as source.
for name in ('evil.php','evil.php84','evil.PHP','evil.phtml','evil.phar','uploads/evil.php'):
 p=Path('/home/lemper/laravel-real/public')/name;p.parent.mkdir(exist_ok=True);p.write_text('<?php echo "UNSAFE-PHP";')
p=Path('/home/lemper/laravel-real/public/assets');p.mkdir(exist_ok=True)
(p/'fixture.txt').write_text('LARAVEL-ASSET')
PY
chown -R lemper:lemper /home/lemper/laravel-real
install -d -o lemper -g lemper -m 0755 /home/lemper/second-app/public
install -d -o lemper -g lemper -m 0755 /home/lemper/logs/nginx /home/lemper/logs/php
cat > /home/lemper/second-app/public/index.php <<'PHP'
<?php header('Content-Type: application/json'); echo json_encode(['app'=>'second', 'php'=>PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION]);
PHP
chown -R lemper:lemper /home/lemper/second-app
cp -a /source/etc/nginx/includes /source/etc/nginx/vhost /etc/nginx/
cp /source/etc/nginx/fastcgi_params /etc/nginx/fastcgi_params
install -d -m 0755 /etc/nginx/site-apps
rm -f /etc/nginx/sites-enabled/default
cat > /etc/nginx/nginx.conf <<'NGINX'
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
bash -c '. /checkout/lib/core/loader.sh; . /checkout/lib/core/deployment.sh; lemper_cli_snapshot /checkout' > "$logs/cli-activation.log" 2>&1
install -m 0600 /checkout/.env /etc/lemper/lemper.conf
# Initial CLI differs from the requested PHP default; site runtimes are explicit.
update-alternatives --set php /usr/bin/php8.3 > "$logs/initial-alternative.log" 2>&1
systemctl restart nginx
cases=0
function uat_case() {
    local name="$1"
    shift
    cases=$((cases+1))
    local result
    set +e
    ( set -e; "$@" ) > "$logs/$name.log" 2>&1
    result=$?
    set -e
    if [[ "$result" == 0 ]]; then printf 'PASS %s\n' "$name";
    else printf 'FAIL %s (log: %s)\n' "$name" "$logs/$name.log"; exit 1; fi
}
function parent_site() {
    lemperctl site create parent-uat.test --type default --runtime php@8.3 --runtime-user lemper --webroot /home/lemper/parent
    printf '<?php header("Content-Type: application/json"); echo json_encode(["app"=>"parent","php"=>PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION]);' > /home/lemper/parent/index.php
    chown lemper:lemper /home/lemper/parent/index.php
}
function encrypt_profile() {
    openssl rand -hex 32 > /etc/lemper/.config_key
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
    python3 - <<'PY'
import json,urllib.request,urllib.error
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args):return None
opener=urllib.request.build_opener(NoRedirect)
def get(host,path,method='GET',data=None):
 req=urllib.request.Request('http://127.0.0.1'+path,headers={'Host':host},method=method,data=data)
 try:r=opener.open(req,timeout=15)
 except urllib.error.HTTPError as error:r=error
 return r.status,r.headers,r.read()
status,headers,body=get('parent-uat.test','/')
assert status==200 and json.loads(body)['php']=='8.3'
for host,prefix,base in [('laravel-uat.test','',''),('parent-uat.test','/demo','/demo')]:
 status,headers,body=get(host,prefix+'/probe/item?x=a%20b')
 assert status==200,(host,status)
 result=json.loads(body);assert result['app']=='laravel-real' and result['php']=='8.4',result
 assert result['base']==base and result['path']=='/probe/item' and result['query']=='a b',result
 status,headers,body=get(host,prefix+'/probe/item/?x=keep%26value')
 assert status==308 and headers['Location'].endswith(prefix+'/probe/item?x=keep%26value'),(host,status,headers.get('Location'))
 status,headers,body=get(host,prefix+'/probe/post/',method='POST',data=b'value=retained')
 assert status==308
 status,headers,body=get(host,prefix+'/probe/post',method='POST',data=b'value=retained')
 assert status==200 and json.loads(body)['method']=='POST' and json.loads(body)['body']=='retained'
 status,headers,body=get(host,prefix+'/probe/encoded%20value/')
 assert status==308 and '%20' in headers['Location']
 for suffix in ['/.env','/composer.json','/evil.php','/evil.php84','/evil.PHP','/evil.phtml','/evil.phar','/uploads/evil.php','/index.php/extra']:
  status,headers,body=get(host,prefix+suffix);assert status==404,(host,suffix,status)
 status,headers,body=get(host,prefix+'/assets/fixture.txt');assert status==200 and body==b'LARAVEL-ASSET'
 status,headers,body=get(host,prefix+'/assets/');assert status==403 and 'Location' not in headers
status,headers,body=get('parent-uat.test','/demo?x=1');assert status==308 and headers['Location'].endswith('/demo/?x=1')
status,headers,body=get('parent-uat.test','/other/');assert status==200 and json.loads(body)['app']=='second'
PY
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
    sed 's/location \/ {/location \/ { auth_basic private;/' "$backup/framework" > "$framework"
    if lemperctl site app add parent-uat.test --mount /protected --webroot /home/lemper/second-app --dry-run; then return 1; fi
    cat "$backup/framework" > "$framework"
    hash=$(printf '%s\n' 'synthetic-uat-pass' | openssl passwd -apr1 -stdin)
    printf 'uat:%s\n' "$hash" > /run/runtime-uat.htpasswd
    chown root:www-data /run/runtime-uat.htpasswd
    chmod 0640 /run/runtime-uat.htpasswd
    sed '/^    root /a\    auth_basic "UAT protected";\n    auth_basic_user_file /run/runtime-uat.htpasswd;' "$backup/parent" > "$parent"
    lemperctl site app add parent-uat.test --mount /protected --webroot /home/lemper/second-app
    python3 - <<'PY'
import base64,json,urllib.request,urllib.error
for path in ['/protected/','/protected/index.php']:
 req=urllib.request.Request('http://127.0.0.1'+path,headers={'Host':'parent-uat.test'})
 try:urllib.request.urlopen(req,timeout=15)
 except urllib.error.HTTPError as error:assert error.code==401
 else:raise RuntimeError('server authentication was bypassed')
token=base64.b64encode(b'uat:synthetic-uat-pass').decode()
req=urllib.request.Request('http://127.0.0.1/protected/',headers={'Host':'parent-uat.test','Authorization':'Basic '+token})
with urllib.request.urlopen(req,timeout=15) as response:assert json.load(response)['app']=='second'
PY
    lemperctl site app remove parent-uat.test --mount /protected --yes
    cat "$backup/parent" > "$parent"
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
