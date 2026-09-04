#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repository_root"

environment_file=${1:-.env}
if [ ! -f "$environment_file" ]; then
  echo "Environment file not found: $environment_file" >&2
  exit 1
fi

set -a
. "$environment_file"
set +a

docker compose --env-file "$environment_file" exec -T \
  -e DDA_CLICKHOUSE_DATABASE \
  -e DDA_CLICKHOUSE_EVENTS_TABLE \
  -e DDA_PLATFORM_WRITER_USER \
  -e DDA_PLATFORM_WRITER_PASSWORD \
  -e DDA_EXPLORER_READER_USER \
  -e DDA_EXPLORER_READER_PASSWORD \
  clickhouse /usr/local/bin/dda-provision-environment
