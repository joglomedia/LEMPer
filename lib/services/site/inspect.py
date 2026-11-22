#!/usr/bin/env python3
# Copyright (c) 2014-2026 MasEDI.Net (https://masedi.net/lemper)
# GNU General Public License; see LICENSE.md.
# Authors: Edi Septriyanto <me@masedi.net>
"""Read public site diagnostics as data; never execute configuration or read keys."""
import configparser
import json
import os
import ssl
import time
from pathlib import Path
import re
import subprocess
import sys

PUBLIC_APP = {"app_uid", "app_framework", "app_db_user", "app_db_name", "app_admin_user", "app_admin_email", "app_webroot"}
SECRET = re.compile(r"password|(?:^|[_\W])pass(?:$|[_\W])|secret|token|authorization|credential|api[_-]?key", re.I)


def read_text(path):
    return path.read_text(encoding="utf-8")


def redact_config(text):
    rendered = []
    for line in text.splitlines():
        # *_pass routing directives are not password fields; URL credentials
        # remain protected even when present in a proxy target.
        route = re.match(r"\s*(?:fastcgi|proxy|uwsgi|scgi|grpc)_pass\s+", line)
        sensitive = (not route and SECRET.search(line)) or re.search(r"^\s*env\[|://[^/\s:@]+:[^/\s@]+@", line)
        rendered.append("# [REDACTED]" if sensitive else line)
    return "\n".join(rendered) + "\n"


def flat_metadata(path, allowed, marker, domain):
    if not path.is_file():
        return None
    if path.is_symlink():
        raise ValueError("symlink metadata")
    values = {}
    for line in read_text(path).splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = re.fullmatch(r"\s*([A-Z_]+)\s*=(.*)", line)
        if not match:
            raise ValueError("invalid metadata")
        key, value = match.groups()
        if value.startswith(('"', "'")):
            if not value.endswith(value[0]):
                raise ValueError("invalid metadata quotes")
            value = value[1:-1]
        if key in allowed:
            values[key.lower()] = value
    if values.get("owner_marker") != marker or values.get("domain") != domain:
        raise ValueError("invalid ownership marker")
    return values


def pool_for_socket(root, socket):
    if not socket or "$" in socket:
        return None
    socket = socket.replace("/var/run/", "/run/", 1)
    for pool in sorted((root / "etc/php").glob("*/fpm/pool.d/*.conf")):
        if pool.is_symlink():
            continue
        text = read_text(pool)
        listen = re.search(r"^\s*listen\s*=\s*([^;\n]+)", text, re.M)
        if listen and listen.group(1).strip().replace("/var/run/", "/run/", 1) == socket:
            return {"file": str(pool), "content": redact_config(text), "listen": socket}
    return None


def certificate(root, configured, domain):
    if not configured.startswith("/") or "$" in configured:
        return {"cert_path": configured, "status": "unresolved"}
    path = root / configured.lstrip("/")
    result = {"cert_path": configured, "type": "letsencrypt" if configured.startswith("/etc/letsencrypt/") else "configured"}
    if configured.startswith("/etc/lemper/ssl/"):
        result["type"] = "self-signed"
    if not path.is_file():
        result["status"] = "missing"
        return result
    args = ["openssl", "x509", "-in", str(path), "-noout", "-subject", "-issuer", "-dates", "-fingerprint", "-sha256", "-ext", "subjectAltName"]
    proc = subprocess.run(args, capture_output=True, text=True, check=False)
    if proc.returncode:
        result["status"] = "invalid"
        return result
    for line in proc.stdout.splitlines():
        for prefix, key in [("subject=", "subject"), ("issuer=", "issuer"), ("notBefore=", "not_before"), ("notAfter=", "not_after"), ("sha256 Fingerprint=", "sha256_fingerprint")]:
            if line.startswith(prefix):
                result[key] = line[len(prefix):]
    result["dns_names"] = re.findall(r"DNS:([^,\s]+)", proc.stdout)
    result["status"] = "readable"
    if result.get("not_after"):
        seconds = ssl.cert_time_to_seconds(result["not_after"]) - time.time()
        result["days_remaining"] = int(seconds // 86400)
        result["expired"] = seconds <= 0
    checked = subprocess.run(["openssl", "x509", "-in", str(path), "-noout", "-checkhost", domain], capture_output=True, check=False)
    result["hostname_matches"] = checked.returncode == 0
    return result


def inspect(domain, root, section="json"):
    vhost = root / "etc/nginx/sites-available" / (domain + ".conf")
    enabled = root / "etc/nginx/sites-enabled" / (domain + ".conf")
    result = {"domain": domain, "vhost_file": str(vhost), "enabled": enabled.is_symlink() and enabled.exists(),
              "nginx_config": None, "fpm_pool": None, "app_metadata": None, "site_metadata": None, "apps": [], "ssl": None}
    text = read_text(vhost) if vhost.is_file() else ""
    if text:
        patterns = {"php_version": r"fastcgi_pass[^;]*php([0-9]+\.[0-9]+)-fpm",
                    "framework": r"include[^;]*vhost/site_([^.]+)\.conf", "fpm_user": r"fastcgi_pass[^;]*fpm\.([a-zA-Z0-9_-]+)\.sock"}
        result["nginx_config"] = {key: (m.group(1) if (m := re.search(pattern, text)) else "") for key, pattern in patterns.items()}
        result["nginx_config"]["content"] = redact_config(text)
        socket = re.search(r"\bfastcgi_pass\s+(?:unix:)?([^;\s]+)", text)
        if section in {"fpm", "all", "json"}:
            result["fpm_pool"] = pool_for_socket(root, socket.group(1) if socket else None)
    if section in {"app", "all", "json"}:
        metadata = root / "etc/lemper/vhost.d" / (domain + ".conf")
        if metadata.is_file():
            if metadata.is_symlink():
                raise ValueError("symlink application metadata")
            parser = configparser.ConfigParser(interpolation=None)
            parser.read_string(read_text(metadata))
            sections = {}
            for metadata_section in parser.sections():
                sections[metadata_section] = {key: "[REDACTED]" if key in {"app_db_pass", "app_admin_pass"} else value.strip('\"\'')
                                     for key, value in parser.items(metadata_section) if key in PUBLIC_APP | {"app_db_pass", "app_admin_pass"}}
            result["app_metadata"] = sections
        result["site_metadata"] = flat_metadata(root / "etc/lemper/sites" / (domain + ".conf"),
            {"OWNER_MARKER", "DOMAIN", "OWNER", "WEBROOT", "RUNTIME", "DATABASE"}, "lemper-site-v1", domain)
        for file in sorted((root / "etc/lemper/site-apps" / domain).rglob("*.conf")):
            app = flat_metadata(file, {"OWNER_MARKER", "DOMAIN", "MOUNT", "TYPE", "OWNER", "WEBROOT", "PUBLIC_ROOT", "RUNTIME"}, "lemper-app-v1", domain)
            result["apps"].append(app)
    if section in {"ssl", "all", "json"}:
        certs = re.findall(r"^\s*ssl_certificate\s+[\"']?([^;\"'\n]+)[\"']?\s*;", text, re.M)
        if not certs:
            for default in [f"/etc/letsencrypt/live/{domain}/fullchain.pem", f"/etc/lemper/ssl/{domain}/cert.pem"]:
                if (root / default.lstrip("/")).is_file():
                    certs.append(default)
        certificates = [certificate(root, path.strip(), domain) for path in certs]
        if certificates:
            result["ssl"] = {"enabled": bool(re.search(r"^\s*ssl_certificate\s", text, re.M)), **certificates[0], "certificates": certificates}
    return result


def render(result, section):
    if section == "json":
        print(json.dumps(result))
        return
    selected = ["config", "fpm", "app", "ssl"] if section == "all" else [section]
    print(f"Domain: {result['domain']}\nEnabled: {'Yes' if result['enabled'] else 'No'}")
    for view in selected:
        value = {"config": result["nginx_config"], "fpm": result["fpm_pool"], "app": {"legacy": result["app_metadata"], "site": result["site_metadata"], "apps": result["apps"]}, "ssl": result["ssl"]}[view]
        print(f"\n{view.upper()}:")
        if isinstance(value, dict) and "content" in value:
            print(value["content"], end="")
        else:
            print(json.dumps(value, indent=2))


def main():
    domain, section = sys.argv[1:]
    if not re.fullmatch(r"(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}\.?", domain) or len(domain) > 253:
        raise ValueError("invalid domain")
    root = Path(os.environ.get("LEMPER_SITE_INSPECT_ROOT", "/"))
    if not root.is_absolute():
        raise ValueError("invalid root")
    result = inspect(domain, root, section)
    if section in {"config", "fpm", "all"} and result["nginx_config"] is None:
        raise ValueError("missing vhost")
    render(result, section)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, UnicodeError, configparser.Error, subprocess.SubprocessError):
        print("Unable to read site diagnostics.", file=sys.stderr)
        sys.exit(1)
