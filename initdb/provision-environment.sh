#!/bin/sh
set -eu

require_identifier() {
  variable_name=$1
  eval "value=\${$variable_name:-}"
  if ! printf '%s' "$value" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$'; then
    echo "$variable_name must be a non-empty ClickHouse identifier." >&2
    exit 1
  fi
}

for variable_name in \
  DDA_CLICKHOUSE_DATABASE \
  DDA_CLICKHOUSE_EVENTS_TABLE \
  DDA_PLATFORM_WRITER_USER \
  DDA_EXPLORER_READER_USER; do
  require_identifier "$variable_name"
done

: "${DDA_PLATFORM_WRITER_PASSWORD:?Set DDA_PLATFORM_WRITER_PASSWORD}"
: "${DDA_EXPLORER_READER_PASSWORD:?Set DDA_EXPLORER_READER_PASSWORD}"

clickhouse_query() {
  clickhouse-client \
    --user "$CLICKHOUSE_USER" \
    --password "$CLICKHOUSE_PASSWORD" \
    "$@"
}

clickhouse_query --query "CREATE DATABASE IF NOT EXISTS \`$DDA_CLICKHOUSE_DATABASE\`"

clickhouse_query --multiquery --query "
CREATE TABLE IF NOT EXISTS \`$DDA_CLICKHOUSE_DATABASE\`.\`$DDA_CLICKHOUSE_EVENTS_TABLE\`
(
  dda_schema_version UInt16,
  dda_event_id UUID,
  dda_received_at DateTime64(3, 'UTC'),
  event_schema_version UInt32,
  event_name LowCardinality(String),
  event_type Nullable(String),
  event_id Nullable(String),
  event_time Nullable(DateTime64(3, 'UTC')),
  device_id Nullable(String),
  user_id Nullable(String),
  profile_id Nullable(UUID),
  user_profile_id Nullable(UUID),
  session_id Nullable(String),
  event_json String
)
ENGINE = ReplacingMergeTree
PARTITION BY toYYYYMM(dda_received_at)
ORDER BY (
  dda_received_at,
  dda_event_id
)
SETTINGS non_replicated_deduplication_window = 1000;
"

clickhouse_query \
  --param_writer_password "$DDA_PLATFORM_WRITER_PASSWORD" \
  --query "CREATE USER IF NOT EXISTS \`$DDA_PLATFORM_WRITER_USER\` IDENTIFIED WITH sha256_password BY {writer_password:String}"
clickhouse_query \
  --param_reader_password "$DDA_EXPLORER_READER_PASSWORD" \
  --query "CREATE USER IF NOT EXISTS \`$DDA_EXPLORER_READER_USER\` IDENTIFIED WITH sha256_password BY {reader_password:String}"

clickhouse_query --query "GRANT INSERT, SELECT ON \`$DDA_CLICKHOUSE_DATABASE\`.\`$DDA_CLICKHOUSE_EVENTS_TABLE\` TO \`$DDA_PLATFORM_WRITER_USER\`"
clickhouse_query --query "GRANT SELECT ON system.tables TO \`$DDA_PLATFORM_WRITER_USER\`"
clickhouse_query --query "GRANT SHOW TABLES ON \`$DDA_CLICKHOUSE_DATABASE\`.* TO \`$DDA_PLATFORM_WRITER_USER\`"
clickhouse_query --query "GRANT SELECT ON \`$DDA_CLICKHOUSE_DATABASE\`.\`$DDA_CLICKHOUSE_EVENTS_TABLE\` TO \`$DDA_EXPLORER_READER_USER\`"

echo "Provisioned exclusive dda_native_v3 table $DDA_CLICKHOUSE_DATABASE.$DDA_CLICKHOUSE_EVENTS_TABLE."
