#!/bin/sh
set -eu

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo "Usage: $0 <source-database> <source-table> <environment-id> [target-env-file]" >&2
  exit 1
fi

source_database=$1
source_table=$2
environment_id=$3
environment_file=${4:-.env}

for identifier in "$source_database" "$source_table"; do
  if ! printf '%s' "$identifier" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$'; then
    echo "Source database and table must be valid ClickHouse identifiers." >&2
    exit 1
  fi
done
if ! printf '%s' "$environment_id" | grep -Eq '^[1-9][0-9]*$'; then
  echo "Environment ID must be a positive integer." >&2
  exit 1
fi

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repository_root"

set -a
. "$environment_file"
set +a

./scripts/provision-environment.sh "$environment_file"

if [ "$source_database.$source_table" = "$DDA_CLICKHOUSE_DATABASE.$DDA_CLICKHOUSE_EVENTS_TABLE" ]; then
  echo "The v2 target table must differ from the v1 source table." >&2
  exit 1
fi

compose() {
  docker compose --env-file "$environment_file" "$@"
}

target_count=$(compose exec -T clickhouse clickhouse-client \
  --user "$CLICKHOUSE_ADMIN_USER" \
  --password "$CLICKHOUSE_ADMIN_PASSWORD" \
  --query "SELECT count() FROM \`$DDA_CLICKHOUSE_DATABASE\`.\`$DDA_CLICKHOUSE_EVENTS_TABLE\`")
if [ "$target_count" != "0" ]; then
  echo "Target table is not empty; refusing a non-idempotent migration." >&2
  exit 1
fi

source_count=$(compose exec -T clickhouse clickhouse-client \
  --user "$CLICKHOUSE_ADMIN_USER" \
  --password "$CLICKHOUSE_ADMIN_PASSWORD" \
  --query "SELECT count() FROM \`$source_database\`.\`$source_table\` WHERE environment_id = $environment_id")

compose exec -T clickhouse clickhouse-client \
  --user "$CLICKHOUSE_ADMIN_USER" \
  --password "$CLICKHOUSE_ADMIN_PASSWORD" \
  --query "INSERT INTO \`$DDA_CLICKHOUSE_DATABASE\`.\`$DDA_CLICKHOUSE_EVENTS_TABLE\`
    (dda_schema_version, dda_event_id, dda_received_at, event_schema_version,
     event_name, event_type, event_id, event_time, client_id, session_id, event_json)
    SELECT 2, dda_event_id, dda_received_at, event_schema_version,
           event_name, event_type, event_id, event_time, client_id, session_id, event_json
    FROM \`$source_database\`.\`$source_table\`
    WHERE environment_id = $environment_id"

migrated_count=$(compose exec -T clickhouse clickhouse-client \
  --user "$CLICKHOUSE_ADMIN_USER" \
  --password "$CLICKHOUSE_ADMIN_PASSWORD" \
  --query "SELECT count() FROM \`$DDA_CLICKHOUSE_DATABASE\`.\`$DDA_CLICKHOUSE_EVENTS_TABLE\`")
if [ "$migrated_count" != "$source_count" ]; then
  echo "Migration count mismatch: source=$source_count target=$migrated_count" >&2
  exit 1
fi

echo "Copied $migrated_count rows into the exclusive dda_native_v2 table."
