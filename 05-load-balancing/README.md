# 05 — Load Balancing

One backend is a single point of failure and a hard ceiling on throughput.
An `upstream` block turns a list of servers into one address that Nginx spreads
traffic across — and quietly stops sending traffic to the ones that stop
answering.

```
                        ┌── app-1 :3001  ✅
  Browser ──▶  Nginx ───┼── app-2 :3002  ✅
                        ├── app-3 :3003  ❌ removed after max_fails
                        └── backup :3009  (only if all of the above are down)
```

---

## Table of Contents

1. [Try it in two minutes](#1-try-it-in-two-minutes)
2. [The algorithms](#2-the-algorithms)
3. [Weights](#3-weights)
4. [Health checks and failover](#4-health-checks-and-failover)
5. [Sticky sessions](#5-sticky-sessions)
6. [Draining a backend for deploys](#6-draining-a-backend-for-deploys)
7. [Seeing what happened](#7-seeing-what-happened)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Try it in two minutes

Start three backends that each announce themselves:

```bash
for p in 3001 3002 3003; do
  node -e "require('http').createServer((q,s)=>s.end('served by :$p\n')).listen($p)" &
done
```

Point Nginx at them with the `backend_rr` upstream from
[`example.conf`](./example.conf), reload, then watch the rotation:

```bash
for i in $(seq 6); do curl -s http://localhost/; done
# served by :3001
# served by :3002
# served by :3003
# served by :3001
# ...
```

Now kill one backend and repeat. After a couple of failed attempts Nginx stops
offering it requests, and traffic keeps flowing.

## 2. The algorithms

```nginx
upstream backend {
    least_conn;                # <- pick one (round robin is the default)
    server 10.0.0.1:3000;
    server 10.0.0.2:3000;
}
```

| Method | Directive | Use when |
|---|---|---|
| **Round robin** | *(default)* | Requests cost roughly the same. The sensible default. |
| **Least connections** | `least_conn;` | Request durations vary — uploads, reports, long queries. |
| **IP hash** | `ip_hash;` | The app keeps sessions in local memory and you can't fix that yet. |
| **Generic hash** | `hash $request_uri consistent;` | Cache nodes — the same URL should always hit the same box. |
| **Random** | `random two least_conn;` | Very large pools, or several independent load balancers. |

`hash ... consistent` uses ketama hashing: adding or removing a node reshuffles
only a small slice of keys instead of the whole map. That matters a lot for
cache tiers.

## 3. Weights

```nginx
upstream backend {
    server 10.0.0.1:3000 weight=3;   # 3 of every 5 requests
    server 10.0.0.2:3000 weight=1;
    server 10.0.0.3:3000 weight=1;
}
```

Weight is relative, not a percentage. Use it when the machines aren't identical,
or to ramp traffic onto a new node gradually (`weight=1`, watch, then raise it).

## 4. Health checks and failover

Open-source Nginx does **passive** health checks — it learns a backend is bad by
failing to talk to it:

```nginx
server 10.0.0.1:3000 max_fails=3 fail_timeout=30s;
```

> 3 failures within 30s → stop sending traffic for 30s, then try one probe again.

Pair it with retry behaviour on the proxy side:

```nginx
proxy_next_upstream       error timeout http_502 http_503 http_504;
proxy_next_upstream_tries 2;
```

> ⚠️ Don't add `non_idempotent` to `proxy_next_upstream` unless you mean it — it
> lets Nginx retry POST/PATCH requests, which can double-charge a card or create
> a record twice.

Active health checks (`health_check` with a real probe URL) are an
**Nginx Plus** feature. On open-source Nginx, use passive checks plus an
external monitor, or put a real health endpoint behind your orchestrator.

## 5. Sticky sessions

`ip_hash` pins a client IP to a backend. It is a workaround, not a design:

- Mobile clients change IP and lose their session.
- Whole offices and CGNAT ranges arrive as one IP, so the balance skews.
- Losing a node reshuffles everyone.

The real fix is stateless app servers: put sessions in Redis, or use signed
cookies/JWTs. Then any backend can serve any request and load balancing
becomes trivial.

## 6. Draining a backend for deploys

```nginx
server 10.0.0.3:3000 down;      # take out of rotation, then reload
```

A zero-downtime rolling deploy:

1. Mark node A `down`, `nginx -s reload` — in-flight requests finish normally.
2. Deploy and verify node A.
3. Remove `down`, reload. Repeat for node B.

`nginx -s reload` never drops a connection: old workers keep serving existing
requests and exit once they're finished.

## 7. Seeing what happened

Log the upstream that served each request:

```nginx
log_format upstreamlog '$remote_addr -> $upstream_addr "$request" $status '
                       'request_time=$request_time '
                       'upstream_time=$upstream_response_time';
```

- `$upstream_addr` — comma-separated if a retry happened (`10.0.0.1:3000, 10.0.0.2:3000`)
- `$request_time` — total, including the client's own slowness
- `$upstream_response_time` — how long the backend actually took

The gap between those last two is your own network/buffering overhead. And for
quick eyeballing during a demo:

```nginx
add_header X-Upstream $upstream_addr always;
```

Drop that header before production — it leaks your internal addresses.

## 8. Troubleshooting

| Symptom | Cause |
|---|---|
| All traffic on one backend | `ip_hash` in use, or you're testing from a single IP |
| `502` even though backends are up | Firewall/security group between Nginx and the backends |
| Sessions randomly logging out | App keeps state locally; needs shared sessions or `ip_hash` |
| A recovered backend gets no traffic | Still inside its `fail_timeout` window — wait it out |
| `no live upstreams while connecting` | Every server is marked failed; check `max_fails` and the backends |

---

## Files

- [`example.conf`](./example.conf) — every algorithm, plus health checks, backup and drain

## Next

[06 — SSL/TLS with Nginx](../06-ssl-with-nginx/) — put HTTPS in front of all this.
