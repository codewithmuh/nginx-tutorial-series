# 06 — SSL/TLS with Nginx

HTTPS is not optional any more: browsers mark plain HTTP as "Not secure",
HTTP/2 effectively requires TLS, and certificates are free. This chapter gets
you from `http://` to an A-grade `https://` — and, just as importantly, keeps it
renewing by itself.

---

## Table of Contents

1. [Get a certificate with Certbot](#1-get-a-certificate-with-certbot)
2. [The HTTPS server block](#2-the-https-server-block)
3. [Redirecting HTTP to HTTPS](#3-redirecting-http-to-https)
4. [Auto-renewal (the part people forget)](#4-auto-renewal-the-part-people-forget)
5. [HSTS — powerful and unforgiving](#5-hsts--powerful-and-unforgiving)
6. [OCSP stapling and session resumption](#6-ocsp-stapling-and-session-resumption)
7. [Self-signed certs for local development](#7-self-signed-certs-for-local-development)
8. [Testing your setup](#8-testing-your-setup)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Get a certificate with Certbot

```bash
sudo apt install certbot python3-certbot-nginx     # Ubuntu/Debian
sudo certbot --nginx -d example.com -d www.example.com
```

`--nginx` edits your config for you and reloads. If you'd rather write the
config yourself (recommended — you learn more and it survives re-runs):

```bash
sudo certbot certonly --nginx -d example.com -d www.example.com
```

Certificates land in `/etc/letsencrypt/live/example.com/`:

| File | What it is |
|---|---|
| `fullchain.pem` | Your cert **+ intermediates** → this is what `ssl_certificate` wants |
| `privkey.pem` | The private key. Never commit, never share. |
| `chain.pem` | Intermediates only → used by `ssl_trusted_certificate` for stapling |
| `cert.pem` | Your cert alone — using this causes "incomplete chain" errors |

**Prerequisites:** DNS for the domain must already point at this server, and
ports 80 and 443 must be open. Certbot proves ownership over port 80.

## 2. The HTTPS server block

```nginx
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;                       # nginx >= 1.25.1
    server_name example.com www.example.com;

    ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:...;

    root /var/www/example.com;
    index index.html;
}
```

On Nginx **older than 1.25.1** the HTTP/2 syntax is `listen 443 ssl http2;`.
Check with `nginx -v`.

`ssl_prefer_server_ciphers off` looks backwards but is current best practice:
modern clients know which cipher their hardware does fastest, so let them
choose from your allowed list.

## 3. Redirecting HTTP to HTTPS

```nginx
server {
    listen 80;
    server_name example.com www.example.com;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/certbot;      # keep renewals working
    }

    location / {
        return 301 https://$host$request_uri;
    }
}
```

Use `return 301`, not `rewrite` — it's faster and can't loop. And keep that
ACME location: redirecting *everything* is the single most common reason
renewals silently start failing.

## 4. Auto-renewal (the part people forget)

Let's Encrypt certificates last 90 days. Certbot installs a systemd timer or
cron job on install — verify it, don't assume it:

```bash
systemctl list-timers | grep certbot     # is the timer armed?
sudo certbot renew --dry-run             # does renewal actually work?
```

The dry run is the important one. It exercises the whole path — challenge,
issuance, reload — without burning rate limits. Run it after any config change
that touches port 80.

Make sure Nginx picks up the new cert after renewal:

```bash
# /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
#!/bin/sh
nginx -t && systemctl reload nginx
```

```bash
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

Set a calendar reminder for day 80 as a backstop. An expired cert is a hard
outage — browsers refuse to load the site at all.

## 5. HSTS — powerful and unforgiving

```nginx
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
```

This tells browsers to refuse plain HTTP for your domain for two years. It kills
the SSL-strip attack window on the very first visit after they've seen it once.

> ⚠️ **You cannot undo this before it expires.** A visitor who has seen the
> header will not be able to reach your site over HTTP even if you remove it.
> With `includeSubDomains`, that applies to *every* subdomain — including that
> internal dashboard that's still HTTP-only.

Safe rollout: start at `max-age=300`, confirm everything works, then raise it.
Only add `preload` (and submit to hstspreload.org) once you're certain — getting
off the preload list takes months.

The `always` flag matters: without it, the header is skipped on error responses
like 404 and 500.

## 6. OCSP stapling and session resumption

Two cheap performance wins:

```nginx
ssl_stapling on;                 # server fetches revocation proof, not the browser
ssl_stapling_verify on;
ssl_trusted_certificate /etc/letsencrypt/live/example.com/chain.pem;
resolver 1.1.1.1 8.8.8.8 valid=300s;   # required — stapling needs DNS

ssl_session_cache   shared:SSL:10m;    # ~40k resumable sessions
ssl_session_timeout 1d;
ssl_session_tickets off;
```

Stapling removes a round trip to the CA on first connect. Session resumption
skips most of the handshake for returning visitors. Verify stapling works:

```bash
echo | openssl s_client -connect example.com:443 -status 2>/dev/null \
  | grep -A1 "OCSP Response Status"
```

## 7. Self-signed certs for local development

```bash
sudo mkdir -p /etc/nginx/certs
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/certs/local.key \
  -out    /etc/nginx/certs/local.crt \
  -subj "/CN=localhost"
```

Point `ssl_certificate` / `ssl_certificate_key` at those and comment out the
stapling block — a self-signed cert has no OCSP responder, and leaving stapling
on fills your error log with warnings.

The browser warning is expected. For a locally-trusted cert with no warning,
use [mkcert](https://github.com/FiloSottile/mkcert).

## 8. Testing your setup

```bash
# Full external audit — aim for A or A+
open https://www.ssllabs.com/ssltest/analyze.html?d=example.com

# What did we actually negotiate?
openssl s_client -connect example.com:443 -tls1_3 </dev/null

# When does it expire?
echo | openssl s_client -connect example.com:443 2>/dev/null \
  | openssl x509 -noout -dates

# Is the redirect a clean 301?
curl -sI http://example.com | head -3
```

## 9. Troubleshooting

| Symptom | Cause |
|---|---|
| `SSL_ERROR_RX_RECORD_TOO_LONG` | You're serving plain HTTP on 443 — missing `ssl` on the `listen` line |
| "Certificate not trusted" on Android/older clients | Used `cert.pem` instead of `fullchain.pem` |
| `ERR_TOO_MANY_REDIRECTS` | App redirects to https too; forward `X-Forwarded-Proto` (chapter 04) |
| Renewal fails after months of working | HTTP→HTTPS redirect now swallows `/.well-known/acme-challenge/` |
| `unknown directive "http2"` | Nginx older than 1.25.1 — use `listen 443 ssl http2;` |
| Cert renewed but site still serves the old one | No reload after renewal — add the deploy hook in §4 |
| Padlock missing on some pages | Mixed content: hardcoded `http://` asset URLs in your HTML |

---

## Files

- [`example.conf`](./example.conf) — full HTTPS setup with redirect, HSTS and stapling

## Next

[07 — URL Rewriting and Redirects](../07-url-rewriting-and-redirects/)
