# 02 — Nginx Basics

Nginx configuration is a small language: a handful of **contexts** that nest,
and **directives** that live inside them. Learn the shape once and every config
you meet afterwards is readable — including the intimidating ones you'll find
on Stack Overflow.

---

## Table of Contents

1. [The shape of a config](#1-the-shape-of-a-config)
2. [Contexts](#2-contexts)
3. [Directives you'll use constantly](#3-directives-youll-use-constantly)
4. [Location blocks and matching order](#4-location-blocks-and-matching-order)
5. [Variables](#5-variables)
6. [Includes](#6-includes)
7. [Managing the service](#7-managing-the-service)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. The shape of a config

Every Nginx config is contexts nested inside contexts:

```nginx
# main context — the process itself
worker_processes auto;

events {                          # how workers accept connections
    worker_connections 1024;
}

http {                            # everything about serving HTTP
    include mime.types;
    gzip on;

    server {                      # one virtual host
        listen 80;
        server_name example.com;

        location / {              # one group of URLs
            root /var/www/html;
        }
    }
}
```

Two rules explain most of what happens:

- **Directives inherit downwards.** `gzip on;` in `http` applies to every server
  and location below it.
- **A directive at a deeper level overrides the inherited one.** `gzip off;` in
  one location affects only that location.

Every directive is only legal in certain contexts. The
[directive index](https://nginx.org/en/docs/dirindex.html) lists the allowed
context for each — worth bookmarking, because "unknown directive" almost always
means "right directive, wrong context".

## 2. Contexts

| Context | Contains | Examples |
|---|---|---|
| **main** | Process-level settings | `user`, `worker_processes`, `pid`, `error_log` |
| **events** | Connection handling | `worker_connections`, `multi_accept` |
| **http** | Everything HTTP | `gzip`, `log_format`, `include`, `upstream` |
| **server** | One virtual host | `listen`, `server_name`, `root`, `ssl_certificate` |
| **location** | One group of URLs | `try_files`, `proxy_pass`, `expires`, `alias` |
| **upstream** | A pool of backends | `server`, `keepalive`, `least_conn` |

[`basic-confg.conf`](./basic-confg.conf) in this folder is a complete nginx.conf
with all of them annotated. Test-drive it without touching your system config:

```bash
nginx -p $(pwd) -c 02-nginx-basics/basic-confg.conf -t
```

## 3. Directives you'll use constantly

```nginx
listen 80;                    # port
listen 443 ssl;               # port + TLS
listen [::]:80;               # IPv6

server_name example.com www.example.com;   # which Host header we answer
server_name *.example.com;                 # wildcard
server_name _;                             # catch-all

root  /var/www/html;          # URI is APPENDED to this path
index index.html index.htm;   # served when the URI is a directory

try_files $uri $uri/ =404;    # first thing that exists wins
return 301 https://$host$request_uri;      # redirect

access_log /var/log/nginx/site.access.log;
error_log  /var/log/nginx/site.error.log warn;
```

Every directive ends in a semicolon. A missing one produces a confusing error
several lines later — `nginx -t` will point at it.

### Serving two sites from one server

That's all `server_name` is for:

```nginx
server {
    listen 80;
    server_name example.com;
    root /var/www/example;
}

server {
    listen 80;
    server_name blog.example.com;
    root /var/www/blog;
}
```

Same port, same machine. Nginx picks the block by the `Host` header the browser
sent. If none match, the **first** block for that port wins — which is why
chapter 08 recommends an explicit catch-all.

## 4. Location blocks and matching order

Locations decide how a group of URLs is handled — and they are **not** checked
top to bottom:

```nginx
location = /health      { }   # 1. exact match — wins immediately
location ^~ /assets/    { }   # 2. prefix match that stops regex checking
location ~* \.(jpg|png)$ { }  # 3. regex (~* = case-insensitive), file order
location /               { }  # 4. longest plain prefix — the fallback
```

The order Nginx actually uses:

1. Exact `=` match → done.
2. Longest `^~` prefix → done, regexes skipped.
3. Regexes `~` / `~*`, **in the order written in the file** → first match wins.
4. Otherwise, the longest plain prefix match.

> This trips up nearly everyone. A regex block near the bottom of your file can
> beat a prefix block at the top. When a location "isn't working", check this
> order first.

Use `=` for hot endpoints like `/health` — it's the fastest match Nginx can do.

## 5. Variables

Nginx exposes the request as variables, and you'll see them everywhere:

| Variable | Value |
|---|---|
| `$uri` | Normalised path, no query string (`/about`) |
| `$request_uri` | Full original URI **with** query string (`/about?x=1`) |
| `$host` | Hostname from the request |
| `$scheme` | `http` or `https` |
| `$remote_addr` | Client IP |
| `$args` / `$query_string` | The query string |
| `$request_method` | `GET`, `POST`, … |
| `$status` | Response status code |

The `$uri` / `$request_uri` distinction matters in redirects: use
`$request_uri` when you want the query string preserved.

Full list: [nginx.org/en/docs/varindex.html](https://nginx.org/en/docs/varindex.html)

## 6. Includes

Split config into files and pull them in:

```nginx
include /etc/nginx/conf.d/*.conf;
include /etc/nginx/sites-enabled/*;
include snippets/ssl-params.conf;
```

This is how `sites-available` / `sites-enabled` works: real files in one
directory, symlinks in the other, and enabling a site means creating a link.
Chapter 12 covers the layout worth adopting.

## 7. Managing the service

```bash
sudo nginx -t            # validate the config
sudo nginx -T            # print the FULL merged config (every include resolved)
sudo nginx -V            # version + compiled-in modules

sudo systemctl reload nginx     # apply changes gracefully
sudo systemctl restart nginx    # full restart — drops connections
sudo systemctl status nginx
```

Two flags to remember:

- **`nginx -t` before every reload.** If it fails, the running config is
  untouched and your site stays up.
- **`nginx -T` when a change "does nothing".** It shows what Nginx actually
  loaded, which is sometimes not the file you edited.

## 8. Troubleshooting

| Message | Meaning |
|---|---|
| `unknown directive "x"` | Wrong context, a typo, or a module that isn't compiled in — check `nginx -V` |
| `directive "x" is not allowed here` | Right directive, wrong context |
| `unexpected "}"` | A missing semicolon on the line above |
| `conflicting server name` | Two server blocks claim the same name and port |
| `duplicate location` | Same location path defined twice in one server block |
| `directory index of "/x/" is forbidden` | No `index` file present and `autoindex` is off |
| Change has no effect | Editing a file nothing includes — verify with `nginx -T` |

---

## Files

- [`basic-confg.conf`](./basic-confg.conf) — a complete annotated `nginx.conf`

## Next

[03 — Hosting Static Websites](../03-hosting-static-websites/) — put this to work.
