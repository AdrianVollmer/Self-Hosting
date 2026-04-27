#!/bin/bash
set -e

# Variables are sourced from /etc/anchorage/anchorage.conf via the systemd unit.
TTL="${TTL:-3600}"

if [ -z "${DOMAIN_SUFFIX:-}" ]; then
  echo "Error: DOMAIN_SUFFIX is not set in /etc/anchorage/anchorage.conf" >&2
  exit 1
fi

if [ -z "${DNS_SERVER:-}" ]; then
  echo "Error: DNS_SERVER is not set in /etc/anchorage/anchorage.conf" >&2
  exit 1
fi

if [ -z "${IP:-}" ]; then
  echo "Error: IP is not set in /etc/anchorage/anchorage.conf" >&2
  exit 1
fi

for DNS_NAME in $(grep -Eo "^[a-z0-9-]+\.${DOMAIN_SUFFIX}" /etc/caddy/anchorage/services.caddy); do
  echo "Registering $DNS_NAME -> $IP"
  nsupdate <<EOF
server ${DNS_SERVER}
update delete ${DNS_NAME} A
update add ${DNS_NAME} ${TTL} A ${IP}
send
EOF
done
