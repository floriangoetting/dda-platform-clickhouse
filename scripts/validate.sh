#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repository_root"

required_files="
.env.example
compose.yaml
config.d/resource-conscious-logging.xml
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

require_logging_setting() {
  required_setting=$1
  if ! grep -F "$required_setting" config.d/resource-conscious-logging.xml >/dev/null; then
    echo "Resource-conscious ClickHouse logging setting is missing: $required_setting" >&2
    exit 1
  fi
}

require_logging_setting '<level>information</level>'
require_logging_setting '<size>50M</size>'
require_logging_setting '<count>3</count>'
require_logging_setting '<ttl>event_date + INTERVAL 1 DAY DELETE</ttl>'
require_logging_setting '<ttl>event_date + INTERVAL 7 DAY DELETE</ttl>'
require_logging_setting '<collect_interval_milliseconds>10000</collect_interval_milliseconds>'

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
