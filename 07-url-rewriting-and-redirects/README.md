# 07 — URL Rewriting and Redirects

Two operations that look alike and behave completely differently:

| | What the browser sees | Directive |
|---|---|---|
| **Redirect** | URL in the address bar **changes**; an extra round trip | `return 301` / `return 302` |
| **Rewrite** | URL **stays the same**; Nginx serves a different path internally | `rewrite ... last` / `try_files` |

Redirect when the resource genuinely moved. Rewrite when you want pretty URLs
in front of an ugly reality.

---

## Table of Contents

1. [Redirects](#1-redirects)
2. [Rewrites](#2-rewrites)
3. [`last` vs `break` vs `permanent` vs `redirect`](#3-last-vs-break-vs-permanent-vs-redirect)
4. [`try_files` — usually the better answer](#4-try_files--usually-the-better-answer)
5. [`root` vs `alias`](#5-root-vs-alias)
6. [Why `if` is evil (and what to use instead)](#6-why-if-is-evil-and-what-to-use-instead)
7. [Location matching order](#7-location-matching-order)
8. [Testing redirects](#8-testing-redirects)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Redirects

```nginx
# Permanent — cached by browsers and search engines, passes SEO ranking
return 301 https://example.com$request_uri;

# Temporary — not cached; maintenance pages, A/B tests, seasonal campaigns
return 302 /promotions/summer;
```

**Choose deliberately.** A 301 is remembered by browsers more or less forever;
shipping one by mistake means users keep hitting the old redirect long after
you fix the config. When in doubt, ship a 302 first.

Canonical host redirect (www → non-www) gets its own server block:

```nginx
server {
    listen 80;
    server_name www.example.com;
    return 301 $scheme://example.com$request_uri;
}
```

Useful variables: `$request_uri` (path **+** query string), `$uri`
(normalised path, no query), `$query_string`, `$scheme`, `$host`.

## 2. Rewrites

```nginx
#        pattern                  replacement        flag
rewrite ^/products/([0-9]+)/?$   /product.php?id=$1  last;
```

Captures in `(...)` become `$1`, `$2`, … Regexes are anchored with `^` and `$`
and matched against the **normalised URI** (no query string, `%20` already
decoded).

## 3. `last` vs `break` vs `permanent` vs `redirect`

| Flag | Effect |
|---|---|
| `last` | Stop rewriting, **restart** the location search with the new URI |
| `break` | Stop rewriting, **stay** in this location and process the new URI here |
| `permanent` | Send a 301 to the client |
| `redirect` | Send a 302 to the client |

The one that matters in practice: **use `break` when the location contains
`proxy_pass`** — `last` would restart matching and probably escape your proxy
block. Use `last` when you want the rewritten URI re-matched against your other
locations.

## 4. `try_files` — usually the better answer

Most rewrites people write are really "serve this if it exists, else that":

```nginx
# Single-page app: real files win, everything else goes to the router
location / {
    try_files $uri $uri/ /index.html;
}

# Extensionless URLs: /about -> /about.html
try_files $uri $uri.html $uri/ =404;

# Fall back to a backend
try_files $uri @app;
location @app { proxy_pass http://127.0.0.1:3000; }
```

`try_files` is faster than a regex chain, and far easier to read six months
later. The last argument is the fallback — either a URI, a named location
(`@app`), or a status code (`=404`).

## 5. `root` vs `alias`

The single most common Nginx misconfiguration:

```nginx
location /downloads/ {
    root /var/www/files;      # /downloads/a.zip -> /var/www/files/downloads/a.zip
}

location /downloads/ {
    alias /var/www/files/;    # /downloads/a.zip -> /var/www/files/a.zip
}
```

> **`root` appends the full URI. `alias` replaces the matched prefix.**

With `alias`, if the location ends in `/` then the alias must too — mismatched
slashes produce 404s that look like permission problems. Prefer `root` whenever
your directory layout can mirror your URL layout.

## 6. Why `if` is evil (and what to use instead)

`if` inside a `location` block is [officially discouraged](https://www.nginx.com/resources/wiki/start/topics/depth/ifisevil/):
only `return` and `rewrite` are reliably safe inside it, and combinations that
look obviously correct can silently do the wrong thing.

Reach for `map` instead. It's evaluated lazily, it's fast, and it stays readable:

```nginx
# http context
map $request_uri $redirect_uri {
    default        "";
    /team.html     /about/team;
    /jobs          https://careers.example.com;
}

# server context
if ($redirect_uri) { return 301 $redirect_uri; }
```

That's the one blessed `if` pattern — a single `return` on a mapped variable —
and it scales to hundreds of legacy URLs without slowing anything down.

For host or scheme conditions, use a separate `server` block rather than an
`if`. That's what server blocks are for.

## 7. Location matching order

Nginx does **not** evaluate locations top to bottom. The order is:

1. `location = /exact` — exact match, wins immediately
2. `location ^~ /prefix/` — longest prefix, and **stops** regex checking
3. `location ~ /regex` / `~* /regex` — first match in **file order**
4. `location /prefix` — longest matching prefix, used if no regex matched

So a regex block near the bottom of your file can beat a prefix block at the
top. When a `location` isn't firing, this ordering is the first thing to check.

## 8. Testing redirects

```bash
# Follow the whole chain and print each hop
curl -sIL http://example.com/old-page | grep -E '^(HTTP|Location)'

# One hop only, with the status code
curl -so /dev/null -w '%{http_code} -> %{redirect_url}\n' http://example.com/old-page
```

Redirect **chains** cost real latency (each hop is a full round trip) and search
engines stop following after a few. Collapse `A → B → C` into `A → C`.

## 9. Troubleshooting

| Symptom | Cause |
|---|---|
| `ERR_TOO_MANY_REDIRECTS` | The redirect target matches the same rule again — exclude it or use `=` matching |
| Rewrite works, then 404s | Used `last` inside a `proxy_pass` location; use `break` |
| Static files 404 under `alias` | Trailing-slash mismatch between `location` and `alias` |
| Redirect not applied at all | Another `location` matched first — see §7 |
| Query string disappears | Used `$uri` where you needed `$request_uri`, or a `?` in the replacement |
| Redirect ignored by the browser | An old 301 is cached — test in a private window or with `curl` |

Debug the rewrite engine itself (noisy — development only):

```nginx
rewrite_log on;
error_log /var/log/nginx/error.log notice;
```

---

## Files

- [`example.conf`](./example.conf) — redirects, rewrites, `try_files`, `alias` and `map`

## Next

[08 — Security with Nginx](../08-security-with-nginx/)
