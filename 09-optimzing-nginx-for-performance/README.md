# 09 — Optimizing Nginx for Performance

Nginx is fast out of the box. Most real gains come from three things — caching,
compression, and not making your app server do work Nginx can do — not from
exotic kernel tuning.

**Measure before and after every change.** A config you can't justify with a
number is superstition.

---

## Table of Contents

1. [Measure first](#1-measure-first)
2. [Workers and connections](#2-workers-and-connections)
3. [Static file delivery](#3-static-file-delivery)
4. [Compression](#4-compression)
5. [Browser caching](#5-browser-caching)
6. [Proxy caching — the big one](#6-proxy-caching--the-big-one)
7. [Upstream keepalive](#7-upstream-keepalive)
8. [Buffers](#8-buffers)
9. [OS-level limits](#9-os-level-limits)
10. [What not to do](#10-what-not-to-do)

---

## 1. Measure first

```bash
# Load test (install: apt install wrk  /  brew install wrk)
wrk -t4 -c100 -d30s https://example.com/

# Where is the time going? Log it.
log_format perf '$request_time $upstream_response_time $upstream_cache_status "$request"';
```

```bash
# Slowest 20 requests in the log
awk '{print $1, $4}' /var/log/nginx/access.log | sort -rn | head -20

# Cache hit rate
awk '{print $3}' /var/log/nginx/access.log | sort | uniq -c | sort -rn
```

- `$request_time` — total, including the client's own network
- `$upstream_response_time` — how long your backend took

If `upstream_response_time` dominates, no amount of Nginx tuning will save you —
fix the backend or cache its output.

## 2. Workers and connections

```nginx
worker_processes     auto;      # = number of CPU cores
worker_rlimit_nofile 65535;

events {
    worker_connections 4096;
    multi_accept       on;
    use                epoll;   # Linux (kqueue on BSD/macOS)
}
```

Theoretical ceiling = `worker_processes × worker_connections`. Halve it for
proxying, since each client request also consumes a connection to the backend.

`worker_connections` above your file-descriptor limit is a lie the kernel will
correct for you — raise `worker_rlimit_nofile` alongside it.

## 3. Static file delivery

```nginx
sendfile    on;      # kernel-to-socket copy; skips user space entirely
tcp_nopush  on;      # fill packets before sending (use with sendfile)
tcp_nodelay on;      # don't delay small responses on keep-alive connections

open_file_cache          max=10000 inactive=30s;
open_file_cache_valid    60s;
open_file_cache_min_uses 2;
open_file_cache_errors   on;
```

`open_file_cache` caches file descriptors and `stat()` results — not contents.
On a site with thousands of small files it removes a huge pile of syscalls.

> Note: it also caches "file not found". During active development, that stale
> negative result is confusing — keep `inactive` short or turn it off locally.

## 4. Compression

```nginx
gzip            on;
gzip_vary       on;
gzip_comp_level 5;
gzip_min_length 1024;
gzip_types text/plain text/css application/json application/javascript
           application/xml image/svg+xml;
```

- **Level 5, not 9.** Level 9 costs meaningfully more CPU for ~2% smaller output.
- **Don't compress images or video.** JPEG/PNG/WebP/MP4 are already compressed;
  gzipping them burns CPU and can grow the file.
- **`text/html` is always compressed** — listing it does nothing.
- **`gzip_vary on`** or shared caches will serve compressed bytes to clients that
  can't decompress them.

Brotli (`ngx_brotli`) beats gzip by 15–20% on text. Worth installing if you
control the build; keep gzip configured as the fallback.

Verify it's working:

```bash
curl -sI -H 'Accept-Encoding: gzip' https://example.com/style.css | grep -i encoding
```

## 5. Browser caching

The fastest request is the one that never leaves the browser.

```nginx
location ~* \.(css|js|woff2|jpg|png|svg|ico)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
    access_log off;
}

location ~* \.html$ {
    expires -1;
    add_header Cache-Control "no-cache";
}
```

This pairing only works if your build fingerprints filenames
(`app.a1b2c3.js`). Cache HTML for a year and your next deploy reaches nobody;
cache fingerprinted assets for a year and repeat visits become nearly free.

## 6. Proxy caching — the big one

```nginx
# http context
proxy_cache_path /var/cache/nginx/proxy levels=1:2 keys_zone=app_cache:10m
                 max_size=2g inactive=60m use_temp_path=off;

# location context
proxy_cache       app_cache;
proxy_cache_valid 200 10m;
proxy_cache_use_stale error timeout updating http_500 http_502 http_503;
proxy_cache_background_update on;
proxy_cache_lock  on;
proxy_cache_bypass $http_authorization $cookie_sessionid;
add_header X-Cache-Status $upstream_cache_status always;
```

Three directives deserve special attention:

- **`proxy_cache_use_stale`** — when the backend errors or times out, serve the
  last good copy instead of a 502. Your users never see the incident.
- **`proxy_cache_lock`** — when a hot entry expires, only *one* request goes to
  the backend; the rest wait for it. Without this, expiry causes a stampede.
- **`proxy_cache_bypass` / `proxy_no_cache`** — never cache authenticated
  responses. Getting this wrong serves one user's account page to another; test
  it deliberately before shipping.

Watch the hit rate:

```bash
awk '{print $NF}' /var/log/nginx/access.log | sort | uniq -c
# HIT / MISS / EXPIRED / STALE / BYPASS / UPDATING
```

## 7. Upstream keepalive

```nginx
upstream app {
    server 127.0.0.1:3000;
    keepalive 64;
}

location / {
    proxy_pass http://app;
    proxy_http_version 1.1;      # required
    proxy_set_header Connection "";   # required — clears "close"
}
```

Without these three lines together, Nginx opens a fresh TCP connection for every
single proxied request. Adding them is often a double-digit latency improvement
for free. All three or none — `keepalive` alone does nothing.

## 8. Buffers

Undersized buffers make Nginx spill requests to disk. Watch for this line:

```
a client request body is buffered to a temporary file
```

If you see it often, raise:

```nginx
client_body_buffer_size 16k;
client_max_body_size    10m;
proxy_buffers           8 16k;
proxy_buffer_size       16k;
```

Don't inflate them blindly — buffers are allocated per connection, so oversized
values multiply into real memory at scale.

## 9. OS-level limits

Nginx can't exceed what the kernel allows:

```bash
# /etc/security/limits.conf
nginx soft nofile 65535
nginx hard nofile 65535
```

```bash
# /etc/sysctl.conf
net.core.somaxconn = 65535           # accept queue depth
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_fin_timeout = 30
```

```bash
sudo sysctl -p
```

Symptom that you need this: `worker_connections are not enough` or connection
refusals under load while CPU sits idle.

## 10. What not to do

| Anti-pattern | Why it hurts |
|---|---|
| `gzip_comp_level 9` | Much more CPU, barely smaller output |
| Gzipping images/video | Wasted CPU, sometimes larger files |
| `worker_processes 32` on 4 cores | Context-switching, no gain |
| Huge `proxy_buffers` everywhere | Memory blows up under concurrency |
| Caching authenticated pages | Serves one user's data to another |
| Copying a whole "optimized nginx.conf" | You inherit someone else's tradeoffs blind |

Change one thing. Measure. Keep it only if the number moved.

---

## Files

- [`example.conf`](./example.conf) — tuned config with caching, compression and buffers

## Next

[10 — Nginx as a Media Server](../10-nginx-as-a-media-server/)
