#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repository_root"

required_files="
.env.example
compose.yaml
initdb/bootstrap.sh
proxy/Caddyfile.example
proxy/nginx.conf.example
proxy/apache-vhost.conf.example
"

for required_file in $required_files; do
  if [ ! -f "$required_file" ]; then
    echo "Missing required file: $required_file" >&2
    exit 1
  fi
done

sh -n initdb/bootstrap.sh
sh -n scripts/validate.sh
sh -n scripts/smoke-test.sh

docker compose version >/dev/null
docker compose --env-file .env.example config --quiet

if grep -Eq 'image:[[:space:]]+[^#]*:latest([[:space:]]|$)' compose.yaml; then
  echo "Container images must not use the latest tag." >&2
  exit 1
fi

required_columns="
dda_schema_version
dda_event_id
dda_batch_id
dda_received_at
organization_id
project_id
environment_id
event_schema_id
event_schema_version
event_name
event_type
event_id
event_time
client_id
session_id
event_json
"

for required_column in $required_columns; do
  if ! grep -Eq "^[[:space:]]+$required_column[[:space:]]" initdb/bootstrap.sh; then
    echo "dda_native_v1 column missing from bootstrap: $required_column" >&2
    exit 1
  fi
done

echo "Deployment kit configuration is valid."
