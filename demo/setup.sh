#!/bin/sh
# Start the containers of the demo, on the current docker context
set -eu

dir=$(cd "$(dirname "$0")" && pwd)
docker compose -f "$dir/compose.yaml" up -d --wait web api || true
docker compose -f "$dir/compose.yaml" up -d cache migrate
