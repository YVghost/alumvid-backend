#!/bin/sh
set -eu
export PORT="${PORT:-8080}"
export LOGISTICA_SERVICE_URL="${LOGISTICA_SERVICE_URL:-http://logistica-service:8083}"
case "$PORT" in *[!0-9]*|'') echo "PORT debe ser numérico" >&2; exit 1;; esac
if [ "$PORT" = 8088 ]; then echo "8088 está reservado al gateway interno" >&2; exit 1; fi
export DNS_RESOLVERS="$(awk '/^nameserver / { if ($2 ~ /:/) printf "[%s] ", $2; else printf "%s ", $2 }' /etc/resolv.conf)"
mkdir -p /tmp/nginx/client /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi
envsubst '${PORT} ${LOGISTICA_SERVICE_URL} ${DNS_RESOLVERS}' < /app/nginx.conf.template > /tmp/nginx.conf
PORT=8088 java -jar /app/app.jar &
java_pid=$!
nginx -e /dev/stderr -c /tmp/nginx.conf -g 'daemon off;' &
nginx_pid=$!
cleanup() { kill "$java_pid" "$nginx_pid" 2>/dev/null || true; }
trap 'cleanup; exit 0' TERM INT
trap cleanup EXIT
while kill -0 "$java_pid" 2>/dev/null && kill -0 "$nginx_pid" 2>/dev/null; do sleep 1; done
exit 1
