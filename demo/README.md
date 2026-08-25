# Demo Stack

A runnable version of [Project 1](../13-real-world-nginx-projects/) — Nginx
serving the static site from chapter 03, with `/api/` proxied to a small Node
container.

Nothing is installed on your machine. Nothing needs `sudo`.

## Run it

```bash
docker compose up
```

## Poke at it

```bash
curl http://localhost:8080/                    # static file from disk
curl http://localhost:8080/api/hello           # proxied to the API container
curl http://localhost:8080/nope                # custom 404 page
curl -I http://localhost:8080/style.css        # Cache-Control: public, 30d
curl -I http://localhost:8080/index.html       # Cache-Control: no-cache
curl -sI http://localhost:8080/ | grep -i x-request-id   # trace id
```

`/api/hello` returns the proxy headers as JSON, so you can see exactly what
Nginx forwarded:

```json
{
  "message": "Hello from the API container",
  "client_ip": "172.18.0.1",
  "forwarded_proto": "http",
  "request_id": "9f2b1c..."
}
```

Comment out a `proxy_set_header` line in
[`nginx/default.conf`](./nginx/default.conf), restart, and watch that field turn
into `"not forwarded"`. That's chapter 04's point in one experiment.

## Change something

```bash
$EDITOR nginx/default.conf
docker compose restart nginx
```

Watch the logs while you test:

```bash
docker compose logs -f nginx
```

## Stop it

```bash
docker compose down
```

## Things worth trying

- Break the config on purpose (delete a `}`) and run
  `docker compose exec nginx nginx -t` to see the error message format.
- Stop the API (`docker compose stop api`) and reload `/api/hello` — that's what
  a `502` looks like, and the error log names the reason.
- Add a `limit_req` zone from [chapter 08](../08-security-with-nginx/) and hammer
  it with `for i in $(seq 50); do curl -so /dev/null -w '%{http_code} ' localhost:8080/; done`
