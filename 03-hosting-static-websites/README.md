# 03 — Hosting Static Websites

Serving static files is what Nginx is best at, and it's the fastest way to get
something real on screen. HTML, CSS, JS, images — plus a React/Vue build, which
is just static files with one extra rule.

This folder ships a small demo site in [`website-files/`](./website-files/) to
serve.

---

## Table of Contents

1. [Try it without installing anything](#1-try-it-without-installing-anything)
2. [Set up the files](#2-set-up-the-files)
3. [The server block](#3-the-server-block)
4. [Apply and test](#4-apply-and-test)
5. [Caching headers](#5-caching-headers)
6. [Compression](#6-compression)
7. [Custom error pages](#7-custom-error-pages)
8. [Serving a single-page app](#8-serving-a-single-page-app)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Try it without installing anything

If you have Docker, the demo site is one command away:

```bash
cd 03-hosting-static-websites
docker run --rm -p 8080:80 \
  -v "$PWD/website-files":/var/www/example.com:ro \
  -v "$PWD/nginx-static.conf":/etc/nginx/conf.d/default.conf:ro \
  nginx:alpine
```

Open **http://localhost:8080**. Try `/about.html`, and `/nope` for the custom
404. The rest of this chapter explains what that config is doing.

## 2. Set up the files

On a real server, put the site somewhere under `/var/www`:

```bash
sudo mkdir -p /var/www/example.com
sudo cp -r website-files/* /var/www/example.com/
```

Nginx's worker processes must be able to read them:

```bash
sudo chown -R www-data:www-data /var/www/example.com   # nginx on RHEL/CentOS
sudo chmod -R 755 /var/www/example.com
```

Permissions are the #1 cause of a mysterious `403 Forbidden` here. Nginx also
needs **execute** permission on every parent directory to traverse into the
folder — that's what `755` on the directories gives you.

## 3. The server block

```nginx
server {
    listen 80;
    server_name example.com www.example.com;

    root  /var/www/example.com;    # disk folder that "/" maps to
    index index.html;              # served when the URI is a directory

    location / {
        try_files $uri $uri/ =404;
    }
}
```

`try_files $uri $uri/ =404` reads as: try the exact file, then the directory
(which triggers `index`), then give up with a 404. It's the workhorse of static
hosting, and it's cheaper than the rewrite rules people often reach for instead.

The full version with caching, gzip and hardening is in
[`nginx-static.conf`](./nginx-static.conf).

## 4. Apply and test

```bash
# Ubuntu/Debian
sudo cp nginx-static.conf /etc/nginx/sites-available/example.com.conf
sudo ln -s /etc/nginx/sites-available/example.com.conf /etc/nginx/sites-enabled/

# CentOS/RHEL
sudo cp nginx-static.conf /etc/nginx/conf.d/example.com.conf

sudo nginx -t          # validate first, always
sudo nginx -s reload
```

```bash
curl -I http://localhost/                 # expect 200
curl -I http://localhost/nope             # expect 404
curl -I http://localhost/style.css        # check Content-Type and Cache-Control
```

Using a real domain? Point its DNS `A` record at your server's IP, and open the
firewall:

```bash
sudo ufw allow 'Nginx Full'
```

## 5. Caching headers

The single biggest speed win on a static site, and it's two rules:

```nginx
# Fingerprinted assets (app.a1b2c3.css) never change — cache them hard
location ~* \.(css|js|jpg|jpeg|png|gif|webp|svg|woff2|ico)$ {
    expires 30d;
    add_header Cache-Control "public";
    access_log off;
}

# HTML must stay fresh, or deploys never reach returning visitors
location ~* \.html$ {
    expires -1;
    add_header Cache-Control "no-cache";
}
```

> ⚠️ Cache HTML for a month and your next deploy reaches nobody who has visited
> before — and you can't undo it from the server. **Long cache on assets,
> no-cache on HTML.**

If your filenames aren't fingerprinted, keep the asset lifetime short
(`expires 1h`) until your build tool adds hashes.

Note that `expires 30d;` *and* `add_header Cache-Control "public";` emit two
`Cache-Control` headers. Clients handle it fine, but a single explicit
`add_header Cache-Control "public, max-age=2592000";` is tidier.

## 6. Compression

```nginx
gzip on;
gzip_min_length 1024;
gzip_types text/plain text/css application/javascript application/json
           image/svg+xml;
```

Typically cuts HTML/CSS/JS transfer size by 60–80%. Don't add images or video —
they're already compressed *(ch. 09)*. `text/html` is always compressed, so
listing it does nothing.

```bash
curl -sI -H 'Accept-Encoding: gzip' http://localhost/style.css | grep -i encoding
```

## 7. Custom error pages

```nginx
error_page 404 /404.html;
location = /404.html {
    internal;         # only reachable via error_page, not by URL
}
```

`internal` stops people browsing directly to `/404.html` and getting a 200.
There's a styled example in [`website-files/404.html`](./website-files/404.html).

## 8. Serving a single-page app

React, Vue and Angular builds are static files plus one rule:

```nginx
location / {
    try_files $uri $uri/ /index.html;    # unknown paths → the router
}
```

Without that fallback, a visitor who refreshes on `/dashboard` gets a 404,
because no such file exists on disk. With it, Nginx hands them `index.html` and
the client-side router takes over.

The full SPA setup — including the API on the same origin — is
[chapter 13, Project 1](../13-real-world-nginx-projects/).

## 9. Troubleshooting

| Symptom | Cause |
|---|---|
| `403 Forbidden` | File permissions, or Nginx can't traverse a parent directory (`755`) |
| `403` on CentOS/RHEL with correct permissions | SELinux: `sudo chcon -Rt httpd_sys_content_t /var/www/example.com` |
| `404` on every page | `root` path is wrong, or points one level too deep — check the error log for the exact path tried |
| Default Nginx page still showing | The default site is still enabled: `sudo rm /etc/nginx/sites-enabled/default` |
| CSS loads as plain text | Missing `include mime.types;` in `nginx.conf` |
| Edits don't appear | Browser cache — hard-reload, or check your `expires` rules |
| Directory listing instead of the page | No `index.html`, and `autoindex on` |

The error log names the exact path Nginx tried to open, which usually ends the
investigation:

```bash
sudo tail -f /var/log/nginx/error.log
```

---

## Files

- [`nginx-static.conf`](./nginx-static.conf) — full static-site config
- [`website-files/`](./website-files/) — demo site: home, about, 404, stylesheet

## Next

[04 — Reverse Proxy with Nginx](../04-reverse-proxy-with-nginx/) — put Nginx in
front of a real application.
