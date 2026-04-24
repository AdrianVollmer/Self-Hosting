#!/bin/bash

set -e

cd "$(dirname "$0")/$SERVICE_NAME"

# Source environment variables
env_vars=""
if [ -f env.app ]; then
	env_vars="$env_vars\n$(cat env.app)"
fi
if [ -f ../env.shared ]; then
	env_vars="$env_vars\n$(cat env.shared)"
fi

run_podman_compose() {
	/usr/bin/podman-compose --env-file <(echo "$env_vars") up -d --force-recreate
}

echo "Environment:"
env | sort

run_podman_compose
