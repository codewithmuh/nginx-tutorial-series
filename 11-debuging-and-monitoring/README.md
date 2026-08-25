# 11 — Debugging and Monitoring

When a site breaks, the answer is almost always already written down in
`/var/log/nginx/error.log`. This chapter is about making that log worth reading
— and about knowing what's happening before someone files a ticket.

---

## Table of Contents

1. [The 60-second triage](#1-the-60-second-triage)
2. [Reading the error log](#2-reading-the-error-log)
3. [Access logs worth querying](#3-access-logs-worth-querying)
4. [Tracing one request end to end](#4-tracing-one-request-end-to-end)
5. [stub_status and Prometheus](#5-stub_status-and-prometheus)
6. [Health check endpoints](#6-health-check-endpoints)
7. [Log analysis one-liners](#7-log-analysis-one-liners)
8. [Log rotation](#8-log-rotation)
9. [Debug builds and single-client tracing](#9-debug-builds-and-single-client-tracing)
10. [Common errors decoded](#10-common-errors-decoded)

---

## 1. The 60-second triage

```bash
sudo nginx -t                              # 1. is the config even valid?
systemctl status nginx                     # 2. is it running?
sudo tail -50 /var/log/nginx/error.log     # 3. what did it say?
ss -tlnp | grep -E ':(80|443)'             # 4. is it listening?
curl -sI http://127.0.0.1/                 # 5. does it answer locally?
```

Step 5 is the fork in the road: if localhost answers but the internet doesn't,
it's DNS or a firewall, not Nginx.

```bash
sudo ufw status                            # host firewall
nginx -T | grep -n 'server_name\|listen'   # full effective config, includes resolved
```

`nginx -T` (capital T) prints the entire merged configuration. When a directive
"isn't working", check here first — you may be editing a file that nothing
includes.

## 2. Reading the error log

```nginx
error_log /var/log/nginx/error.log warn;
```

Levels, quietest to loudest: `emerg alert crit error warn notice info debug`.
Set `warn` in production, drop to `info` while chasing something.

Each line names the client, the request and the upstream:

```
2026/03/14 09:12:44 [error] 1234#0: *56789 connect() failed (111: Connection refused)
  while connecting to upstream, client: 203.0.113.9, server: example.com,
  request: "GET /api/users HTTP/1.1", upstream: "http://127.0.0.1:3000/api/users",
  host: "example.com"
```

That single line tells you: the backend on port 3000 is not listening. No
guessing required.

## 3. Access logs worth querying

The default `combined` format doesn't record timings, so it can't answer "why
was it slow". Use something richer:

```nginx
log_format detailed '$remote_addr - $remote_user [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    'rt=$request_time uct=$upstream_connect_time '
                    'uht=$upstream_header_time urt=$upstream_response_time '
                    'cache=$upstream_cache_status upstream=$upstream_addr';
```

| Variable | Meaning |
|---|---|
| `$request_time` | Total time, **including** the client's slow network |
| `$upstream_connect_time` | Time to establish the backend connection |
| `$upstream_header_time` | Until the backend's first byte — your app's real think time |
| `$upstream_response_time` | Until the backend finished |
| `$upstream_cache_status` | HIT / MISS / EXPIRED / STALE / BYPASS |

Shipping to a log platform? Use the JSON format in
[`example.conf`](./example.conf) — `escape=json` handles quotes in user agents
so one weird request can't corrupt your pipeline.

### Log only the interesting requests

```nginx
map $status $is_error { ~^[45] 1; default 0; }
access_log /var/log/nginx/problems.log detailed if=$is_error;
```

A small "problems only" log next to the firehose is the one you'll actually read.

## 4. Tracing one request end to end

```nginx
add_header X-Request-ID $request_id always;              # give it to the client
proxy_set_header X-Request-ID $request_id;               # give it to the backend
```

`$request_id` is a unique hex string per request. Log it on both sides, return it
in the response, and a user's screenshot becomes a grep:

```bash
grep 8f3a2b1c /var/log/nginx/access.json.log /var/log/app/app.log
```

This one line of config saves hours during an incident.

## 5. stub_status and Prometheus

```nginx
location = /nginx_status {
    stub_status;
    allow 127.0.0.1;
    deny  all;
    access_log off;
}
```

```
Active connections: 43
server accepts handled requests
 10231 10231 42891
Reading: 0 Writing: 5 Waiting: 38
```

- **accepts ≠ handled** → you hit a resource limit; check `worker_connections`
  and file descriptors.
- **requests ÷ handled** → requests per connection. Near 1.0 means keep-alive
  isn't being used.
- **Waiting** → idle keep-alive connections. Normal, and usually the biggest
  number.

Feed it to Prometheus with the
[nginx-prometheus-exporter](https://github.com/nginxinc/nginx-prometheus-exporter):

```bash
docker run -p 9113:9113 nginx/nginx-prometheus-exporter:latest \
  -nginx.scrape-uri=http://host.docker.internal/nginx_status
```

Alert on: 5xx rate, p95 `request_time`, upstream failures, cache hit rate drop,
and certificate expiry (chapter 06).

> ⚠️ Never expose `/nginx_status` publicly — it's free reconnaissance about your
> traffic and capacity.

## 6. Health check endpoints

Two endpoints, two different questions:

```nginx
location = /healthz {          # shallow: is Nginx alive?
    access_log off;
    return 200 "ok\n";
}

location = /readyz {           # deep: is the whole stack alive?
    access_log off;
    proxy_pass http://127.0.0.1:3000/health;
    proxy_connect_timeout 2s;
    proxy_read_timeout    2s;
}
```

Keep them distinct. If your load balancer's health check hits a deep endpoint
that touches the database, one slow query can pull every node out of rotation at
once.

## 7. Log analysis one-liners

```bash
# Top 20 client IPs
awk '{print $1}' access.log | sort | uniq -c | sort -rn | head -20

# Status code breakdown
awk '{print $9}' access.log | sort | uniq -c | sort -rn

# Every 5xx in the last stretch, with the URL
awk '$9 ~ /^5/ {print $9, $7}' access.log | sort | uniq -c | sort -rn

# Slowest requests (with the `detailed` format above)
grep -o 'rt=[0-9.]*' access.log | sort -t= -k2 -rn | head -20

# Requests per minute — spot a spike
awk '{print substr($4,2,17)}' access.log | uniq -c

# Cache hit rate
grep -o 'cache=[A-Z]*' access.log | sort | uniq -c | sort -rn

# 404s worth fixing (real links, not bot noise)
awk '$9 == 404 {print $7}' access.log | sort | uniq -c | sort -rn | head -20
```

With JSON logs, `jq` is cleaner:

```bash
jq -r 'select(.status >= 500) | "\(.time) \(.status) \(.request_uri)"' access.json.log
jq -s 'map(.request_time) | add/length' access.json.log      # mean response time
```

## 8. Log rotation

Busy sites fill disks, and a full disk takes Nginx down hard. Distro packages
install a logrotate config already; check it exists:

```bash
cat /etc/logrotate.d/nginx
sudo logrotate -d /etc/logrotate.d/nginx     # dry run
```

The essential part is the post-rotate signal:

```
postrotate
    [ -f /var/run/nginx.pid ] && kill -USR1 `cat /var/run/nginx.pid`
endscript
```

`USR1` makes Nginx reopen its log files. Without it, Nginx keeps writing to the
renamed (or deleted) file and the disk fills anyway while the new log stays
empty.

## 9. Debug builds and single-client tracing

```bash
nginx -V 2>&1 | grep -o with-debug
```

If present, you can trace exactly one IP instead of flooding the disk:

```nginx
error_log /var/log/nginx/debug.log debug;

events {
    debug_connection 203.0.113.42;
}
```

Debug logging is enormous — gigabytes per minute on a busy server. Scope it to
one client, and turn it off when you're done.

Also useful:

```nginx
rewrite_log on;             # logs rewrite decisions at "notice" level
error_log /var/log/nginx/error.log notice;
```

## 10. Common errors decoded

| Log message | What it means |
|---|---|
| `connect() failed (111: Connection refused)` | Backend isn't listening on that port |
| `no live upstreams while connecting to upstream` | Every backend marked failed by `max_fails` |
| `upstream timed out (110: Connection timed out)` | Backend slower than `proxy_read_timeout` |
| `13: Permission denied` opening a file | File permissions, or SELinux — check `ls -l` and `audit.log` |
| `24: Too many open files` | Raise `worker_rlimit_nofile` and the OS `nofile` limit |
| `worker_connections are not enough` | Raise `worker_connections` (chapter 09) |
| `client intended to send too large body` | Raise `client_max_body_size` |
| `upstream sent too big header` | Raise `proxy_buffer_size` / `proxy_buffers` |
| `SSL_do_handshake() failed` | Protocol/cipher mismatch, or a client speaking plain HTTP to :443 |
| `directory index of "..." is forbidden` | No `index` file and `autoindex` is off |
| `bind() to 0.0.0.0:80 failed (98: Address in use)` | Apache or another Nginx already holds the port |

---

## Files

- [`example.conf`](./example.conf) — log formats, request IDs, stub_status and health checks

## Next

[12 — Best Practices and Resources](../12-best-practises-and-resources/)
