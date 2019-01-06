#!/usr/bin/env bash
set -euo pipefail

chmod 770 /tokaido/logs/varnish
chown varnish:web /tokaido/logs/varnish

VARNISH_BYPASS="${VARNISH_BYPASS:-false}"
VARNISH_PURGE_KEY="${VARNISH_PURGE_KEY:-}"
NGINX_HOSTNAME="${NGINX_HOSTNAME:-nginx}"

echo "config value 'VARNISH_BYPASS'     :: ${VARNISH_BYPASS}"
echo "config value 'VARNISH_PURGE_KEY'  :: ${VARNISH_PURGE_KEY}"
echo "config value 'NGINX_HOSTNAME'     :: ${NGINX_HOSTNAME}"

sed -i "s/{{.VARNISH_BYPASS}}/${VARNISH_BYPASS}/g" /etc/varnish/default.vcl
sed -i "s/{{.NGINX_HOSTNAME}}/${NGINX_HOSTNAME}/g" /etc/varnish/default.vcl
sed -i "s/{{.VARNISH_PURGE_KEY}}/${VARNISH_PURGE_KEY}/g" /etc/varnish/default.vcl

exec /usr/bin/supervisord -n