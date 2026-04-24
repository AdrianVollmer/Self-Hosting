#!/bin/bash

set -e

cd "$(dirname "$0")/$SERVICE_NAME"

# Source environment variables
env_vars=""
for file in env.app ../env.shared ; do
  if [ -f $file ]; then
    env_vars="$env_vars$(cat "$file")"
  fi
done

run_podman_compose() {
	/usr/bin/podman-compose --env-file <(echo "$env_vars") up -d --force-recreate
}

echo "Environment:"
env | sort

run_podman_compose
