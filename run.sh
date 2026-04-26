#!/bin/bash
# Working directory is set to /opt/anchorage/$SERVICE_NAME by the systemd unit.

set -e

env_vars=""
for file in env.app ../env.shared; do
  if [ -f "$file" ]; then
    env_vars="${env_vars}${env_vars:+$'\n'}$(cat "$file")"
  fi
done

/usr/bin/podman-compose --env-file <(echo "$env_vars") up -d --force-recreate
