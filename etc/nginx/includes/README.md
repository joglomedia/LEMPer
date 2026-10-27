Nginx Server-directive Config Files
----------------------

Each file is included from a `server {}` block or a `location {}` block, not
from the `http {}` block. The installer copies the directory as-is; files are
opt-in, so unused includes do not affect `nginx -t`.

| Group | Files | Included by |
|---|---|---|
| PHP | `php_handler.conf`, `php_handlers.conf` | Default and generated vhosts |
| Monitoring | `monitoring.conf` | Default vhosts (loopback only) |
| Security | `rules_security.conf`, `rules_restriction.conf`, `rules_staticfiles.conf`, `security_headers.conf` | Every vhost |
| Compression | `compression_gzip.conf`, `compression_brotli.conf` | One per vhost |
| TLS | `ssl.conf`, `http3.conf` (generated when `NGINX_HTTP3=true`) | HTTPS vhosts |
| Cache | `cache_static.conf`, `fastcgi_cache.conf`, `rules_fastcgi_cache.conf`, `proxy_cache.conf` | Opt-in per vhost |
| WAF | `modsec.conf` (generated), `naxsi.rules`, `naxsi_core.rules` | Opt-in per vhost |
| Errors / CGI | `error_pages.conf`, `fcgiwrap.conf` | Opt-in per vhost |

Include order matters. Security and restriction rules must come before the
broader static-file regex locations, otherwise a regex location can shadow a
`deny` rule. The shipped vhosts follow:

```nginx
include /etc/nginx/includes/compression_gzip.conf;
include /etc/nginx/includes/rules_security.conf;
include /etc/nginx/includes/rules_restriction.conf;
include /etc/nginx/includes/rules_staticfiles.conf;
include /etc/nginx/vhost/site_<framework>.conf;

set $php_version "8.5";
include /etc/nginx/includes/php_handlers.conf;
```

`php_handlers.conf` defines `.php` plus the versioned `.php85`–`.php82`
handlers. Include it again inside a prefix location (such as the
basic-auth protected `/lcp` area) to inherit that location's access rules.

As LEMPer stack requirements, please DO NOT remove any files contained here.
