#!/bin/bash

set -e

cd "$(dirname "$0")/$SERVICE_NAME"

env_vars=""
for file in env.app ../env.shared; do
  if [ -f "$file" ]; then
    env_vars="${env_vars}${env_vars:+$'\n'}$(cat "$file")"
  fi
done

/usr/bin/podman-compose --env-file <(echo "$env_vars") up -d --force-recreate
