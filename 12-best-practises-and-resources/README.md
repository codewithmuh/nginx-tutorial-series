# 12 — Best Practices and Resources

Eleven chapters of directives, distilled into the habits that keep an Nginx
setup working a year from now — plus the references worth bookmarking.

---

## Table of Contents

1. [Config organisation](#1-config-organisation)
2. [The deploy ritual](#2-the-deploy-ritual)
3. [Production checklist](#3-production-checklist)
4. [Common mistakes](#4-common-mistakes)
5. [Directive quick reference](#5-directive-quick-reference)
6. [Useful commands](#6-useful-commands)
7. [Resources](#7-resources)

---

## 1. Config organisation

One file per site, shared settings in snippets:

```
/etc/nginx/
├── nginx.conf                     # global: workers, http defaults
├── snippets/
│   ├── ssl-params.conf            # protocols, ciphers, stapling
│   ├── security-headers.conf      # the add_header block
│   └── proxy-params.conf          # the proxy_set_header block
├── sites-available/
│   ├── example.com.conf
│   └── api.example.com.conf
└── sites-enabled/
    └── example.com.conf -> ../sites-available/example.com.conf
```

```nginx
server {
    include snippets/ssl-params.conf;
    include snippets/security-headers.conf;

    location @app {
        proxy_pass http://app_backend;
        include snippets/proxy-params.conf;
    }
}
```

Why it's worth the setup:

- A TLS change is **one** edit, not twenty.
- `sites-available` / `sites-enabled` lets you disable a site by removing a
  symlink — no deleting, no commenting out 80 lines.
- Site files stay short enough to read in one screen.

On RHEL/CentOS the convention is `conf.d/*.conf` with no enabled/available
split. Either is fine — just be consistent.

**Keep `/etc/nginx` in version control.** A `git diff` after an incident is worth
more than any amount of remembering.

## 2. The deploy ritual

```bash
sudo nginx -t          # 1. validate — ALWAYS
sudo nginx -s reload   # 2. graceful reload, zero dropped connections
curl -sI https://example.com | head -1    # 3. verify
```

Never `restart` when `reload` will do. Reload starts new workers with the new
config while old workers finish their in-flight requests, then exit. Restart
drops every connection.

If `nginx -t` fails, **the old config is still running** — you have time to fix
it. That's why the test comes first, every time.

Confirm what's actually loaded (not what you think you edited):

```bash
nginx -T | less
```

## 3. Production checklist

**Before going live**

- [ ] `nginx -t` passes
- [ ] HTTPS with a valid cert; HTTP redirects to it *(ch. 06)*
- [ ] `certbot renew --dry-run` passes, deploy hook reloads Nginx
- [ ] `server_tokens off` *(ch. 08)*
- [ ] Security headers with `always` *(ch. 08)*
- [ ] `default_server` returning 444 for unknown hosts
- [ ] Dotfiles and backup extensions denied
- [ ] `client_max_body_size` matches real uploads
- [ ] Rate limits on login and API paths
- [ ] gzip on for text, off for media *(ch. 09)*
- [ ] Static assets `expires 1y`, HTML `no-cache`
- [ ] Upstream `keepalive` + `proxy_http_version 1.1` + `Connection ""`
- [ ] Health endpoint for the load balancer *(ch. 11)*
- [ ] Access logs include timings; logrotate configured
- [ ] `/etc/nginx` committed to git

**Ongoing**

- [ ] Alerts on 5xx rate, p95 latency, cert expiry
- [ ] Security updates applied (`unattended-upgrades`)
- [ ] Cache hit rate watched — a sudden drop means something changed
- [ ] `nginx -T` diffed after every change

## 4. Common mistakes

| Mistake | Consequence | Fix |
|---|---|---|
| `add_header` in a location | **Silently drops all inherited headers** | Re-declare them there, or keep them at server level |
| `if` inside `location` | Unpredictable behaviour | Use `map`, `try_files`, or a separate server block *(ch. 07)* |
| `root` where `alias` belongs | 404s on static files | `root` appends the URI; `alias` replaces the prefix |
| `keepalive` without `proxy_http_version 1.1` | Silently does nothing | Always set all three directives together |
| Redirecting `/.well-known/` to HTTPS | Cert renewal fails, site expires | Carve out the ACME path *(ch. 06)* |
| `rewrite ... last` in a proxy location | Escapes the proxy block | Use `break` |
| Caching authenticated responses | One user sees another's data | `proxy_cache_bypass` on session cookie/auth header |
| `expires 1y` on HTML | Deploys never reach returning visitors | `no-cache` for HTML, long expiry for fingerprinted assets |
| `limit_req` with no `burst` | Real users get 429s | `burst=20 nodelay` |
| Logs never rotated | Disk fills, server dies | logrotate with the `USR1` postrotate signal *(ch. 11)* |

## 5. Directive quick reference

```nginx
# --- Serving ---
listen 443 ssl;  http2 on;      # port + TLS + HTTP/2
server_name example.com;        # which Host header this block answers
root /var/www/site;             # URI is APPENDED to this path
alias /var/www/files/;          # matched prefix is REPLACED by this path
index index.html;
try_files $uri $uri/ =404;      # first that exists wins; last arg = fallback

# --- Redirect / rewrite ---
return 301 https://$host$request_uri;
rewrite ^/old/(.*)$ /new/$1 last;      # last = re-match; break = stay here

# --- Proxying ---
proxy_pass http://backend;             # trailing slash changes everything
proxy_set_header Host $host;
proxy_http_version 1.1;
proxy_read_timeout 60s;

# --- Caching ---
expires 1y;  add_header Cache-Control "public, immutable";
proxy_cache app_cache;  proxy_cache_valid 200 10m;

# --- Limits ---
client_max_body_size 10m;
limit_req zone=general burst=20 nodelay;
limit_conn addr 20;

# --- Access ---
allow 10.0.0.0/8;  deny all;           # order matters, first match wins
auth_basic "Restricted";  auth_basic_user_file /etc/nginx/.htpasswd;
```

**Location matching order** (not top-to-bottom!):
`= exact` → `^~ prefix` → `~ regex` in file order → longest plain prefix.

## 6. Useful commands

```bash
nginx -t                     # validate config
nginx -T                     # print the FULL merged config
nginx -V                     # version + compiled-in modules
nginx -s reload              # graceful reload
nginx -s quit                # graceful shutdown (stop = immediate)

systemctl reload nginx
systemctl status nginx
journalctl -u nginx -n 50 --no-pager

tail -f /var/log/nginx/error.log
ss -tlnp | grep nginx        # what's listening
nginx -V 2>&1 | tr ' ' '\n' | grep with-   # is that module compiled in?
```

Two flags people forget: **`-T`** answers "why isn't my change taking effect",
and **`-V`** answers "why is that directive unknown".

## 7. Resources

**Official**
- [Nginx documentation](https://nginx.org/en/docs/) — the directive reference; the alphabetical index is your friend
- [Directive index](https://nginx.org/en/docs/dirindex.html) — every directive with its allowed context
- [Variable index](https://nginx.org/en/docs/varindex.html) — every `$variable`
- [Beginner's guide](https://nginx.org/en/docs/beginners_guide.html)
- [Pitfalls and common mistakes](https://www.nginx.com/resources/wiki/start/topics/tutorials/config_pitfalls/) — read this once a year
- [If is Evil](https://www.nginx.com/resources/wiki/start/topics/depth/ifisevil/)

**Tools**
- [Mozilla SSL Config Generator](https://ssl-config.mozilla.org/) — generates a modern TLS block for your exact Nginx version
- [SSL Labs Server Test](https://www.ssllabs.com/ssltest/) — grade your HTTPS
- [securityheaders.com](https://securityheaders.com/) — grade your headers
- [digitalocean.com/community/tools/nginx](https://www.digitalocean.com/community/tools/nginx) — config generator
- [GoAccess](https://goaccess.io/) — real-time log dashboard in the terminal
- [nginx-prometheus-exporter](https://github.com/nginxinc/nginx-prometheus-exporter)
- [Certbot](https://certbot.eff.org/) — free certificates, auto-renewed

**Books and deeper reading**
- *Nginx HTTP Server* — Clément Nedelcu
- *Nginx Cookbook* — Derek DeJonghe (free from F5)
- [Nginx source](https://github.com/nginx/nginx) — the answer when the docs are ambiguous

---

## Files

- [`example.conf`](./example.conf) — the snippet layout plus a complete production site

## Next

[13 — Real-World Nginx Projects](../13-real-world-nginx-projects/) — put it all together.
