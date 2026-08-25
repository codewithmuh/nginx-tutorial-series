# 13 — Real-World Nginx Projects

Five complete setups, each one a pattern you'll meet on real servers. Every
snippet here composes the pieces from the earlier chapters, so if a directive
looks unfamiliar the chapter that explains it is linked.

---

## Table of Contents

1. [SPA + API on one domain](#project-1--spa--api-on-one-domain)
2. [WordPress / PHP-FPM](#project-2--wordpress--php-fpm)
3. [API gateway for microservices](#project-3--api-gateway-for-microservices)
4. [Maintenance mode](#project-4--maintenance-mode)
5. [Blue-green deployment](#project-5--blue-green-deployment)
6. [Run the demo stack locally](#run-the-demo-stack-locally)

---

## Project 1 — SPA + API on one domain

**Problem:** A React/Vue build plus an API. Put them on different domains and
you inherit CORS, preflight requests and cookie headaches.

**Solution:** Serve both from one origin. Static files from disk, `/api/` proxied
to the backend.

```nginx
root /var/www/app/dist;

location /assets/ {                     # fingerprinted by Vite/webpack
    expires 1y;
    add_header Cache-Control "public, immutable";
}

location /api/ {
    proxy_pass http://spa_api;
    proxy_set_header Host $host;
}

location = /index.html {                # must never be cached
    expires -1;
    add_header Cache-Control "no-cache";
}

location / {
    try_files $uri $uri/ /index.html;   # client-side routing
}
```

Two lines carry this whole setup:

- **`try_files $uri $uri/ /index.html`** — without it, refreshing on
  `/dashboard` returns 404, because no such file exists. Nginx hands the router
  its own entry point instead.
- **`no-cache` on `index.html`** — cache it and returning users keep loading the
  old bundle after every deploy, while their browser insists everything is fine.

*Uses: [ch. 03](../03-hosting-static-websites/), [ch. 04](../04-reverse-proxy-with-nginx/), [ch. 09](../09-optimzing-nginx-for-performance/)*

## Project 2 — WordPress / PHP-FPM

**Problem:** PHP isn't a web server. Nginx has to hand `.php` requests to
PHP-FPM over FastCGI, and do it without opening a remote-code-execution hole.

```nginx
location / {
    try_files $uri $uri/ /index.php?$args;    # permalinks
}

location ~ \.php$ {
    try_files $uri =404;                      # ← the security-critical line
    include        fastcgi_params;
    fastcgi_pass   unix:/run/php/php8.2-fpm.sock;
    fastcgi_param  SCRIPT_FILENAME $document_root$fastcgi_script_name;
}

location = /xmlrpc.php               { deny all; }
location ~* /uploads/.*\.php$        { deny all; }
```

> ⚠️ **`try_files $uri =404;` inside the PHP block is not optional.** Without it,
> a request for `/uploads/photo.jpg/evil.php` can get PHP to execute the uploaded
> file. This is one of the most exploited WordPress misconfigurations there is.

Also: block `xmlrpc.php` (a brute-force amplifier nobody uses any more), deny
PHP execution anywhere inside upload directories, and rate-limit `wp-login.php`
([ch. 08](../08-security-with-nginx/)).

## Project 3 — API gateway for microservices

**Problem:** Six services, six ports. Clients shouldn't know or care.

```nginx
upstream svc_users  { server 127.0.0.1:4001; keepalive 16; }
upstream svc_orders { server 127.0.0.1:4002; keepalive 16; }

server {
    server_name api.example.com;

    proxy_set_header X-Request-ID $request_id;    # one ID across all services

    location /v1/users/  { proxy_pass http://svc_users/;  }
    location /v1/orders/ { proxy_pass http://svc_orders/; }

    location /v1/search/ {
        proxy_pass http://svc_search/;
        proxy_cache_valid 200 5m;
        limit_req zone=api burst=10 nodelay;
    }
}
```

Note the **trailing slash** on `proxy_pass http://svc_users/;` — it strips
`/v1/users/` before forwarding, so the service sees `/profile`, not
`/v1/users/profile` ([ch. 04](../04-reverse-proxy-with-nginx/)).

Setting `X-Request-ID` at the server level means every service logs the same ID
for one user action — the difference between minutes and hours when debugging a
distributed request ([ch. 11](../11-debuging-and-monitoring/)).

## Project 4 — Maintenance mode

**Problem:** Take the site down for a migration without deploying a config
change, and without search engines de-indexing you.

```nginx
set $maintenance 0;
if (-f /var/www/maintenance.on)   { set $maintenance 1; }
if ($remote_addr = 203.0.113.42)  { set $maintenance 0; }   # you get through
if ($maintenance = 1)             { return 503; }

error_page 503 @maintenance;
location @maintenance {
    root /var/www/maintenance;
    rewrite ^ /index.html break;
    add_header Retry-After 3600 always;
}
```

```bash
sudo touch /var/www/maintenance.on    # maintenance on  — no reload needed
sudo rm    /var/www/maintenance.on    # maintenance off
```

**503, not 200.** A maintenance page served as 200 tells Google your content is
now "we'll be right back" — and it will happily index that. 503 plus
`Retry-After` says "temporary, come back later" and costs you no ranking.

The IP exception lets you verify the deploy while everyone else waits.

## Project 5 — Blue-green deployment

**Problem:** Deploy with zero downtime, and roll back in seconds when the new
version misbehaves.

Two identical environments. One serves traffic, the other is idle and gets the
new release:

```nginx
upstream blue  { server 127.0.0.1:5001; }
upstream green { server 127.0.0.1:5002; }

set $active_backend "blue";        # keep this line in its own included file

location / {
    proxy_pass http://$active_backend;
}

location /_green/ { proxy_pass http://green/; }   # smoke-test the idle side
```

The workflow:

1. Deploy to **green** (idle).
2. Verify through `/_green/` — real server, real config, no user traffic.
3. Change the include to `"green"`, run `nginx -t && nginx -s reload`.
4. Watch. If anything looks wrong, change it back and reload — **rollback is
   seconds, not a redeploy.**
5. Green is now live; blue becomes the idle target for next time.

Keep the switch in its own tiny included file so the change is one line and the
`git diff` is unmistakable.

## Run the demo stack locally

The repo ships a working version of Project 1 — Nginx in front of a tiny API,
serving the static site from chapter 03:

```bash
cd demo
docker compose up
```

Then:

```bash
curl http://localhost:8080/            # static file, served by Nginx
curl http://localhost:8080/api/hello   # proxied to the API container
curl -I http://localhost:8080/style.css   # check the Cache-Control header
```

Edit `demo/nginx/default.conf`, then `docker compose restart nginx` to see your
change. Nothing is installed on your machine and nothing needs sudo.

---

## Files

- [`example.conf`](./example.conf) — all five projects, fully commented
- [`../demo/`](../demo/) — the runnable Docker version of Project 1

## Where to go next

You've covered the whole series. Good places to keep going:

- Put a CDN in front of this setup and re-check your cache headers
- Move the config into Ansible/Terraform so servers are reproducible
- Read the [pitfalls list](https://www.nginx.com/resources/wiki/start/topics/tutorials/config_pitfalls/) once more — it lands differently now
- Break something on purpose in the demo stack and fix it from the error log

Back to the [series index](../README.md).
