#!/bin/bash
# Working directory is set to /var/lib/anchorage/$SERVICE_NAME by the systemd unit.

set -e

env_vars=""
for file in env.app ../env.shared; do
  if [ -f "$file" ]; then
    env_vars="${env_vars}${env_vars:+$'\n'}$(cat "$file")"
  fi
done

if [ -n "$env_vars" ]; then
  /usr/bin/podman-compose --env-file <(echo "$env_vars") up -d --force-recreate
else
  /usr/bin/podman-compose up -d --force-recreate
fi
