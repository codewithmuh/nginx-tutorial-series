# 01 — Introduction to Nginx

Welcome. By the end of this chapter you'll have Nginx installed, running, and
serving a page — and you'll know what it's actually for.

---

## Table of Contents

1. [What is Nginx?](#1-what-is-nginx)
2. [Why people choose it](#2-why-people-choose-it)
3. [Nginx vs Apache](#3-nginx-vs-apache)
4. [Installing](#4-installing)
5. [Starting and stopping](#5-starting-and-stopping)
6. [Where the config lives](#6-where-the-config-lives)
7. [Your first change](#7-your-first-change)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. What is Nginx?

Nginx (pronounced "engine X") is a web server — but that undersells it. The same
binary is also:

- **Reverse proxy** — takes requests and forwards them to your app *(ch. 04)*
- **Load balancer** — spreads traffic across many servers *(ch. 05)*
- **Cache** — stores responses so your backend stops repeating itself *(ch. 09)*
- **TLS terminator** — handles HTTPS so your app doesn't have to *(ch. 06)*
- **Media server** — streams video with seeking and throttling *(ch. 10)*

In practice, most production Nginx installs do several of these at once.

It was written by Igor Sysoev in 2004 to solve the **C10k problem**: how to
serve 10,000 simultaneous connections on one machine. Apache's answer at the
time was a process or thread per connection, which runs out of memory long
before 10,000. Nginx uses an **event loop** instead — a small, fixed number of
worker processes, each juggling thousands of connections, none of them blocked
waiting on a slow client.

That one architectural decision is why Nginx uses so little memory under load,
and it's worth understanding early. Everything else in this series follows from
it.

```
        Apache (prefork)                    Nginx (event-driven)

   request ─▶ [process] ─┐            request ─┐
   request ─▶ [process] ─┼─▶ files    request ─┼─▶ [worker] ─▶ files
   request ─▶ [process] ─┘            request ─┘   (one process,
   (one process each,                              thousands of
    memory grows fast)                             connections)
```

## 2. Why people choose it

| | |
|---|---|
| **Speed on static files** | Hands files from disk to socket inside the kernel (`sendfile`) |
| **Low, predictable memory** | Concurrency doesn't multiply processes |
| **One tool, many jobs** | Web server, proxy, balancer, cache — same config language |
| **Everywhere** | Powers a large share of the busiest sites on the internet |
| **Great docs** | [nginx.org/en/docs](https://nginx.org/en/docs/) is precise and complete |

## 3. Nginx vs Apache

Both are excellent. They differ in ways that matter:

| | Nginx | Apache |
|---|---|---|
| **Architecture** | Event-driven, async | Process/thread per connection *(mpm_event narrows this)* |
| **Static files** | Very fast | Slower |
| **Config** | Central files, no per-directory overrides | `.htaccess` per directory |
| **Dynamic content** | Proxies to PHP-FPM / app servers | Can embed interpreters (`mod_php`) |
| **Config reload** | Graceful, zero dropped connections | Graceful too |

The `.htaccess` difference is the practical one: Apache checks for those files
on *every request*, which is convenient on shared hosting and slow everywhere
else. Nginx has no equivalent — all config is central, read once at startup.
That's why an Nginx change needs a reload, and why it's faster.

## 4. Installing

**Ubuntu / Debian**

```bash
sudo apt update
sudo apt install nginx
```

**CentOS / RHEL / Fedora**

```bash
sudo dnf install nginx      # or: sudo yum install nginx
```

**macOS (Homebrew)**

```bash
brew install nginx
```

**Docker** — no install at all:

```bash
docker run --rm -p 8080:80 nginx:alpine
```

Confirm it's there, and note the version — a few directives in later chapters
depend on it:

```bash
nginx -v
```

## 5. Starting and stopping

**Linux (systemd)**

```bash
sudo systemctl start nginx
sudo systemctl stop nginx
sudo systemctl reload nginx      # apply config changes, no dropped connections
sudo systemctl enable nginx      # start on boot
sudo systemctl status nginx
```

**macOS (Homebrew)**

```bash
brew services start nginx
brew services stop nginx
brew services restart nginx
```

**Anywhere**

```bash
sudo nginx -t          # test the config — do this before every reload
sudo nginx -s reload   # graceful reload
sudo nginx -s quit     # graceful shutdown
```

> **Reload, don't restart.** A reload starts new workers with the new config
> while the old ones finish their in-flight requests. A restart drops every
> connection. And if `nginx -t` fails, the running config is untouched — which
> is exactly why you test first.

Now visit **http://localhost** (Ubuntu/CentOS) or **http://localhost:8080**
(Homebrew default) and you should see the Nginx welcome page.

## 6. Where the config lives

| Platform | Main config | Site configs |
|---|---|---|
| Ubuntu/Debian | `/etc/nginx/nginx.conf` | `/etc/nginx/sites-available/` + symlink into `sites-enabled/` |
| CentOS/RHEL | `/etc/nginx/nginx.conf` | `/etc/nginx/conf.d/*.conf` |
| macOS (Apple Silicon) | `/opt/homebrew/etc/nginx/nginx.conf` | `/opt/homebrew/etc/nginx/servers/` |
| macOS (Intel) | `/usr/local/etc/nginx/nginx.conf` | `/usr/local/etc/nginx/servers/` |

Not sure? Ask Nginx itself:

```bash
nginx -t         # prints the path of the config it tested
nginx -V         # shows --conf-path and every compiled-in module
```

Logs are usually in `/var/log/nginx/` (`access.log` and `error.log`). When
something is broken, `error.log` almost always says why.

## 7. Your first change

Homebrew's Nginx listens on 8080 by default; Linux packages use 80. Either way,
changing the port is a good first edit:

```bash
sudo nano /etc/nginx/nginx.conf          # macOS: /opt/homebrew/etc/nginx/nginx.conf
```

Find the `listen` line and change the port:

```nginx
server {
    listen 8000;          # was 80
    server_name localhost;
    ...
}
```

Then the ritual you'll repeat for the rest of your career:

```bash
sudo nginx -t            # 1. validate
sudo nginx -s reload     # 2. apply
curl -I http://localhost:8000/    # 3. verify
```

[`example-config.conf`](./example-config.conf) in this folder is a complete,
commented version of a minimal site config — read it next.

## 8. Troubleshooting

| Symptom | Fix |
|---|---|
| `bind() to 0.0.0.0:80 failed (98: Address already in use)` | Apache or another Nginx has the port: `sudo ss -tlnp \| grep :80` |
| Welcome page doesn't load | Is it running? `systemctl status nginx`. Firewall? `sudo ufw allow 'Nginx Full'` |
| `nginx: command not found` after brew install | `/opt/homebrew/bin` isn't on your `PATH` |
| Changes have no effect | You edited a file nothing includes — check with `nginx -T` |
| Permission denied on port 80 | Ports below 1024 need root: use `sudo` |

---

## Files

- [`example-config.conf`](./example-config.conf) — a minimal, fully commented server block

## Next

[02 — Nginx Basics](../02-nginx-basics/) — read and write any Nginx config with
confidence.
