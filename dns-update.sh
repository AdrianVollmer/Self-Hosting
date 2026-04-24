#!/bin/bash
set -x

TTL="${TTL:-3600}"
DNS_SERVER="${DNS_SERVER:-192.168.178.1}"
SUFFIX="${SUFFIX:-fritz.box}"

for DNS_NAME in $(grep -Eo "^[a-z-]+.$SUFFIX" /etc/caddy/Caddyfile); do
  nsupdate <<EOF
server ${DNS_SERVER}
update delete ${DNS_NAME} A
update add ${DNS_NAME} ${TTL} A ${IP}
send
EOF
done
