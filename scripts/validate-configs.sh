#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Validate every .conf in this repo with a real Nginx.
#
#   ./scripts/validate-configs.sh
#
# Uses Docker (nginx:alpine) when available so results are identical on every
# machine, and falls back to a locally installed nginx.
#
# Most files here are server-block snippets meant to be included inside an
# http { } context, so each one is wrapped in a minimal nginx.conf before
# being tested. Files that already contain "events {" are tested as-is.
# ---------------------------------------------------------------------------
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; RESET=$'\033[0m'
pass=0; fail=0; failed_files=()

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
WORK_CERTS="$WORK/certs"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    RUNNER="docker"
    CERT_DIR="/certs"
    echo "Validating with Docker (nginx:alpine)"
elif command -v nginx >/dev/null 2>&1; then
    RUNNER="local"
    CERT_DIR="$WORK_CERTS"
    echo "Validating with local nginx ($(nginx -v 2>&1))"
else
    echo "${RED}Neither Docker nor nginx found. Install one of them.${RESET}"
    exit 1
fi
echo

# Self-signed cert so the SSL chapters can be checked for real.
mkdir -p "$WORK/certs"
openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -keyout "$WORK/certs/test.key" -out "$WORK/certs/test.crt" \
    -subj "/CN=localhost" >/dev/null 2>&1

if [ "$RUNNER" = "local" ]; then
    # The local runner uses $WORK as the nginx prefix, so `include mime.types;`
    # must resolve there.
    NGINX_PREFIX="$(nginx -V 2>&1 | tr ' ' '\n' | sed -n 's/^--prefix=//p')"
    for candidate in "$NGINX_PREFIX/conf/mime.types" "$NGINX_PREFIX/mime.types" \
                     /etc/nginx/mime.types /opt/homebrew/etc/nginx/mime.types \
                     /usr/local/etc/nginx/mime.types; do
        [ -f "$candidate" ] && { cp "$candidate" "$WORK/mime.types"; break; }
    done
    [ -f "$WORK/mime.types" ] || echo "types { }" > "$WORK/mime.types"
    for candidate in "$NGINX_PREFIX/conf/fastcgi_params" "$NGINX_PREFIX/fastcgi_params" \
                     /etc/nginx/fastcgi_params /opt/homebrew/etc/nginx/fastcgi_params \
                     /usr/local/etc/nginx/fastcgi_params; do
        [ -f "$candidate" ] && { cp "$candidate" "$WORK/fastcgi_params"; break; }
    done
    [ -f "$WORK/fastcgi_params" ] || : > "$WORK/fastcgi_params"
fi
mkdir -p "$WORK/logs" "$WORK/cache"

build_wrapper() {
    # $1 = conf file, $2 = destination nginx.conf
    local src="$1" dst="$2"

    # Point every certificate directive at the throwaway cert, and disable
    # stapling (a self-signed cert has no OCSP responder).
    sed -E \
        -e "s|^([[:space:]]*)ssl_certificate_key[[:space:]]+.*;|\\1ssl_certificate_key ${CERT_DIR}/test.key;|" \
        -e "s|^([[:space:]]*)ssl_certificate[[:space:]]+.*;|\\1ssl_certificate ${CERT_DIR}/test.crt;|" \
        -e "s|^([[:space:]]*)ssl_trusted_certificate[[:space:]]+.*;|\\1ssl_trusted_certificate ${CERT_DIR}/test.crt;|" \
        -e "s|^([[:space:]]*)(ssl_stapling[a-z_]*[[:space:]]+on;)|\\1# \\2|" \
        -e "s|/var/log/nginx|${WORK}/logs|g" \
        -e "s|^([[:space:]]*)pid[[:space:]]+.*;|\1pid ${WORK}/nginx.pid;|" \
        -e "s|^([[:space:]]*)(aio[[:space:]]+threads;)|\1# \2  # Linux only|" \
        -e "s|/var/cache/nginx|${WORK}/cache|g" \
        "$src" > "$WORK/snippet.conf"

    if grep -q '^[[:space:]]*events[[:space:]]*{' "$src"; then
        # Already a complete nginx.conf.
        cp "$WORK/snippet.conf" "$dst"
    else
        {
            echo "worker_processes 1;"
            echo "pid /tmp/nginx-validate.pid;"
            echo "events { worker_connections 64; }"
            echo "http {"
            echo "    include mime.types;"
            echo "    default_type application/octet-stream;"
            cat "$WORK/snippet.conf"
            echo "}"
        } > "$dst"
    fi
}

check() {
    local file="$1"
    build_wrapper "$file" "$WORK/nginx.conf"

    local out
    if [ "$RUNNER" = "docker" ]; then
        out=$(docker run --rm \
                -v "$WORK/nginx.conf":/etc/nginx/nginx.conf:ro \
                -v "$WORK/certs":/certs:ro \
                nginx:alpine nginx -t 2>&1)
    else
        out=$(nginx -t -c "$WORK/nginx.conf" -p "$WORK" 2>&1)
    fi

    if [ $? -eq 0 ]; then
        printf '%s  %s\n' "${GREEN}PASS${RESET}" "$file"
        pass=$((pass + 1))
    else
        printf '%s  %s\n' "${RED}FAIL${RESET}" "$file"
        echo "$out" | sed 's/^/        /'
        fail=$((fail + 1))
        failed_files+=("$file")
    fi
}

# Configs whose upstreams only resolve inside their own Docker network.
# `docker compose up` in demo/ is what actually exercises these.
SKIP_LIST=("./demo/nginx/default.conf")

while IFS= read -r conf; do
    [ -s "$conf" ] || { printf '%s  %s (empty)\n' "${YELLOW}SKIP${RESET}" "$conf"; continue; }
    skip=0
    for entry in "${SKIP_LIST[@]}"; do
        [ "$conf" = "$entry" ] && skip=1
    done
    if [ "$skip" = 1 ]; then
        printf '%s  %s (needs its compose network; run `docker compose up` in demo/)\n' \
            "${YELLOW}SKIP${RESET}" "$conf"
        continue
    fi
    check "$conf"
done < <(find . -name '*.conf' -not -path './.git/*' | sort)

echo
echo "──────────────────────────────────────────"
printf '%s passed, %s failed\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
    printf '%sFailing files:%s\n' "$RED" "$RESET"
    printf '  %s\n' "${failed_files[@]}"
    exit 1
fi
printf '%sAll configs are valid.%s\n' "$GREEN" "$RESET"
