# 04 — Reverse Proxy with Nginx

Your app server can serve HTTP on its own. So why put Nginx in front of it?

Because a reverse proxy gives you TLS termination, static-file serving, caching,
compression, rate limiting, timeouts and a stable public port — none of which
your app framework should be spending CPU on. Your app binds to `127.0.0.1:3000`
and stops being reachable from the internet at all.

```
                     ┌──────────────────────┐
  Browser ──:443──▶  │  Nginx               │ ──:3000──▶  Node / Django / Rails
                     │  TLS, gzip, static,  │ ──:8000──▶  a second service
                     │  caching, timeouts   │
                     └──────────────────────┘
```

---

## Table of Contents

1. [Run a backend to proxy to](#1-run-a-backend-to-proxy-to)
2. [The minimal proxy](#2-the-minimal-proxy)
3. [The headers you must forward](#3-the-headers-you-must-forward)
4. [WebSockets](#4-websockets)
5. [Serving static files yourself](#5-serving-static-files-yourself)
6. [Timeouts and buffering](#6-timeouts-and-buffering)
7. [Caching backend responses](#7-caching-backend-responses)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Run a backend to proxy to

Any HTTP server will do. A one-liner:

```bash
python3 -m http.server 3000
```

Or a tiny Node app:

```bash
node -e "require('http').createServer((q,s)=>{s.end('hello from :3000 '+q.url)}).listen(3000)"
```

Confirm it answers before involving Nginx — half of all "Nginx is broken"
reports are a backend that never started:

```bash
curl -i http://127.0.0.1:3000/
```

## 2. The minimal proxy

```nginx
server {
    listen 80;
    server_name app.example.com;

    location / {
        proxy_pass http://127.0.0.1:3000;
    }
}
```

That works — and it is also wrong in production, because your app now thinks
every visitor is `127.0.0.1` talking plain HTTP. Read on.

### The trailing-slash rule for `proxy_pass`

This trips up everyone, once:

| Config | Request | Backend receives |
|---|---|---|
| `location /api/ { proxy_pass http://b; }`  | `/api/users` | `/api/users` |
| `location /api/ { proxy_pass http://b/; }` | `/api/users` | `/users` |

**No trailing slash → the URI is passed through untouched. A trailing slash (or
any path) → the matched `location` prefix is stripped and replaced.**

## 3. The headers you must forward

```nginx
proxy_set_header Host              $host;
proxy_set_header X-Real-IP         $remote_addr;
proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
```

| Header | Without it |
|---|---|
| `Host` | Backend gets `Host: app_backend`; virtual hosting and absolute redirects break |
| `X-Real-IP` | Every log line and rate limit sees `127.0.0.1` |
| `X-Forwarded-For` | You lose the client IP chain behind a CDN |
| `X-Forwarded-Proto` | The app builds `http://` links on an HTTPS site → mixed content, redirect loops |

Your framework must be told to trust these: `app.set('trust proxy', 1)` in
Express, `USE_X_FORWARDED_HOST` / `SECURE_PROXY_SSL_HEADER` in Django,
`ForwardedHeaders` middleware in ASP.NET.

> ⚠️ Only trust `X-Forwarded-*` from proxies you control. If your Nginx is
> internet-facing, a client can forge these headers — use
> [`real_ip_header`](https://nginx.org/en/docs/http/ngx_http_realip_module.html)
> with `set_real_ip_from` to accept them only from your CDN's ranges.

## 4. WebSockets

WebSockets start as an HTTP request that asks to be upgraded. Nginx drops
hop-by-hop headers by default, so you must forward the handshake explicitly:

```nginx
location /ws/ {
    proxy_pass http://app_backend;
    proxy_http_version 1.1;
    proxy_set_header Upgrade    $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 7d;      # otherwise idle sockets die after 60s
}
```

Symptom when this is missing: the connection opens, then closes with code 1006
about a minute later.

## 5. Serving static files yourself

Never proxy `/static/` to a Python or Node process:

```nginx
location /static/ {
    alias /var/www/app/static/;
    expires 30d;
    access_log off;
}
```

`root` appends the whole URI to the path; `alias` replaces the matched prefix.
With `root /var/www/app/static/`, a request for `/static/app.css` would look for
`/var/www/app/static/static/app.css`. Chapter 07 covers this in detail.

## 6. Timeouts and buffering

```nginx
proxy_connect_timeout 5s;    # TCP connect — should be fast or not at all
proxy_read_timeout   60s;    # silence from the backend before giving up
client_max_body_size 10m;    # 413 above this, before the body reaches the app
```

Nginx buffers the whole backend response by default, which protects your app
from slow clients. Turn it off **only** for streaming (SSE, long-poll,
progressive downloads):

```nginx
proxy_buffering off;
```

## 7. Caching backend responses

Cache what your backend keeps regenerating identically:

```nginx
# http context
proxy_cache_path /var/cache/nginx/app levels=1:2 keys_zone=app_cache:10m
                 max_size=1g inactive=60m;

# location context
proxy_cache app_cache;
proxy_cache_valid 200 10m;
proxy_cache_valid 404 1m;
proxy_cache_use_stale error timeout updating http_500 http_502 http_503;
add_header X-Cache-Status $upstream_cache_status;   # HIT / MISS / EXPIRED
```

`proxy_cache_use_stale` is the quiet hero: if the backend falls over, visitors
keep getting the last good copy instead of a 502.

## 8. Troubleshooting

| Symptom | Usual cause |
|---|---|
| `502 Bad Gateway` | Backend isn't running, or is on a different port. Check `curl 127.0.0.1:3000` and the error log. |
| `502` on SELinux (RHEL/Fedora) | `setsebool -P httpd_can_network_connect 1` |
| `504 Gateway Timeout` | Backend slower than `proxy_read_timeout` |
| Redirect loop | Missing `X-Forwarded-Proto` — app redirects http→https forever |
| CSS/JS 404 behind the proxy | `root` used where `alias` was needed |
| WebSocket closes after ~60s | Missing `Upgrade`/`Connection` headers or low `proxy_read_timeout` |

Read the actual error, always:

```bash
sudo tail -f /var/log/nginx/error.log
```

---

## Files

- [`example.conf`](./example.conf) — full annotated reverse-proxy server block

## Next

[05 — Load Balancing](../05-load-balancing/) — one upstream, many backends.
