# 08 — Security with Nginx

Nginx isn't a firewall or a WAF, but it is the first thing that touches every
request — which makes it the cheapest place to stop a very large share of the
attacks and noise that hit any public server.

Everything here is defensive: header hygiene, rate limits, size caps, access
rules. Apply it to your own servers.

---

## Table of Contents

1. [Hide the version](#1-hide-the-version)
2. [Security headers](#2-security-headers)
3. [Rate limiting](#3-rate-limiting)
4. [Connection and size limits](#4-connection-and-size-limits)
5. [Blocking files that shouldn't be public](#5-blocking-files-that-shouldnt-be-public)
6. [IP allow-lists and basic auth](#6-ip-allow-lists-and-basic-auth)
7. [Catch-all server block](#7-catch-all-server-block)
8. [Running behind a CDN](#8-running-behind-a-cdn)
9. [Checklist and testing](#9-checklist-and-testing)

---

## 1. Hide the version

```nginx
server_tokens off;
```

`Server: nginx/1.24.0` tells a scanner exactly which CVE list to try. This
doesn't make you secure — patching does — but it removes free reconnaissance.

## 2. Security headers

```nginx
add_header X-Content-Type-Options    "nosniff" always;
add_header X-Frame-Options           "SAMEORIGIN" always;
add_header Referrer-Policy           "strict-origin-when-cross-origin" always;
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
add_header Permissions-Policy        "geolocation=(), microphone=(), camera=()" always;
```

| Header | Stops |
|---|---|
| `X-Content-Type-Options: nosniff` | Browsers guessing a `.txt` upload is JavaScript |
| `X-Frame-Options` | Clickjacking — your site framed inside an attacker's page |
| `Referrer-Policy` | Leaking full URLs (with tokens in them) to third parties |
| `Strict-Transport-Security` | Downgrade / SSL-strip attacks (see chapter 06 — read the warning) |
| `Permissions-Policy` | Embedded content silently reaching for camera/mic/location |

> ⚠️ **`add_header` does not merge.** If a `location` block has its own
> `add_header`, it discards **every** header inherited from the server block.
> Re-declare them in that location, or keep all of them at the server level.

### Content-Security-Policy

The strongest anti-XSS control available, and the easiest to break your own site
with. Roll it out in report-only mode first:

```nginx
add_header Content-Security-Policy-Report-Only
    "default-src 'self'; object-src 'none'; frame-ancestors 'self'" always;
```

Watch the console, fix what breaks, then rename the header to
`Content-Security-Policy` to start enforcing. `'unsafe-inline'` in `script-src`
defeats most of the point — remove it as soon as your inline scripts are gone.

## 3. Rate limiting

Define zones in the `http` context, apply them per location:

```nginx
limit_req_zone $binary_remote_addr zone=general:10m rate=30r/s;
limit_req_zone $binary_remote_addr zone=login:10m   rate=5r/m;
limit_req_status 429;

location = /login {
    limit_req zone=login burst=3 nodelay;
}
```

- `rate=5r/m` — five requests per minute per IP. Brute-forcing a password at
  that rate takes centuries.
- `burst=20` — allow a short spike. **Without a burst, ordinary page loads get
  429s**, because a browser fetches a dozen assets at once.
- `nodelay` — serve the burst immediately rather than spacing it out. Almost
  always what you want for web traffic.
- `10m` of zone memory tracks roughly 160,000 addresses.

Tune it by watching, not guessing:

```bash
grep 'limiting requests' /var/log/nginx/error.log | tail -50
```

If real users appear in there, your limit is too tight.

## 4. Connection and size limits

```nginx
limit_conn_zone $binary_remote_addr zone=addr:10m;
limit_conn addr 20;             # max 20 concurrent connections per IP

client_max_body_size   10m;     # reject big uploads with 413
client_header_timeout  10s;     # slow-loris defence
client_body_timeout    10s;
send_timeout           10s;
```

Slow-loris attacks work by opening many connections and sending headers one byte
at a time. Short header/body timeouts plus a per-IP connection cap make it
ineffective.

## 5. Blocking files that shouldn't be public

```nginx
location ~ /\.(?!well-known) {
    deny all;
    access_log off;
    log_not_found off;
}

location ~* \.(bak|old|orig|save|swp|sql|log|ini|conf)$ {
    deny all;
}
```

The first rule blocks `.git/`, `.env`, `.htpasswd` and friends — a deployed
`.git` directory hands an attacker your entire source history, credentials
included. The `(?!well-known)` exception keeps Let's Encrypt renewals working.

Test it:

```bash
curl -sI https://example.com/.env      | head -1   # expect 403
curl -sI https://example.com/.git/HEAD | head -1   # expect 403
```

## 6. IP allow-lists and basic auth

```nginx
location /admin/ {
    allow 203.0.113.0/24;    # office
    allow 10.0.0.0/8;        # VPN
    deny  all;
}

location /internal/ {
    auth_basic           "Restricted area";
    auth_basic_user_file /etc/nginx/.htpasswd;
}
```

```bash
sudo htpasswd -c /etc/nginx/.htpasswd alice    # -c only for the first user
```

Rules are evaluated in order, first match wins — so `deny all` goes **last**.
Basic auth is a speed bump, not an auth system: it's plaintext credentials on
every request, so it only makes sense over HTTPS, and never as your app's real
login.

## 7. Catch-all server block

Bots scan by IP address and send garbage `Host` headers. Give them nothing:

```nginx
server {
    listen 80  default_server;
    listen 443 ssl default_server;
    server_name _;

    ssl_certificate     /etc/nginx/certs/dummy.crt;
    ssl_certificate_key /etc/nginx/certs/dummy.key;

    return 444;      # Nginx-specific: close the connection, send nothing
}
```

Without this, the first server block in your config answers for every unmatched
host — which is usually your real site.

## 8. Running behind a CDN

Behind Cloudflare or a load balancer, `$remote_addr` is the CDN's IP — so every
rate limit applies to the CDN as a whole, not per user:

```nginx
set_real_ip_from 173.245.48.0/20;    # the CDN's ranges (keep this list updated)
real_ip_header   CF-Connecting-IP;
real_ip_recursive on;
```

> ⚠️ Only list ranges you actually trust. Any client can *send* a
> `CF-Connecting-IP` header; `set_real_ip_from` is what decides whose claim is
> believed. Also make sure your origin only accepts traffic from the CDN —
> otherwise attackers reach it directly and skip every rule above.

## 9. Checklist and testing

- [ ] `server_tokens off;`
- [ ] TLS 1.2/1.3 only, HTTP redirects to HTTPS (chapter 06)
- [ ] Security headers set with `always`
- [ ] Rate limits on `/login` and `/api/`
- [ ] `client_max_body_size` sized to your real uploads
- [ ] Dotfiles and backup extensions denied
- [ ] Admin paths behind allow-list or auth
- [ ] `default_server` returning 444
- [ ] Nginx and OS patched; automatic security updates on
- [ ] Logs monitored (chapter 11)

```bash
# Header audit
curl -sI https://example.com | grep -iE 'strict|x-frame|x-content|referrer|server'

# Independent grades
open https://securityheaders.com/?q=example.com
open https://www.ssllabs.com/ssltest/analyze.html?d=example.com

# Rate limit actually firing? (expect 429s to appear)
for i in $(seq 40); do curl -so /dev/null -w '%{http_code} ' https://example.com/login; done
```

Run these against servers you own or have written permission to test.

---

## Files

- [`example.conf`](./example.conf) — hardened server block with every control above

## Next

[09 — Optimizing Nginx for Performance](../09-optimzing-nginx-for-performance/)
