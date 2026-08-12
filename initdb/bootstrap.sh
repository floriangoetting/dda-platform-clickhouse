#!/bin/sh
set -eu

clickhouse_query() {
  clickhouse-client \
    --user "$CLICKHOUSE_USER" \
    --password "$CLICKHOUSE_PASSWORD" \
    "$@"
}

clickhouse_query --query "CREATE DATABASE IF NOT EXISTS analytics"

clickhouse_query --multiquery --query "
CREATE TABLE IF NOT EXISTS analytics.events
(
  dda_schema_version UInt16,
  dda_event_id UUID,
  dda_batch_id UUID,
  dda_received_at DateTime64(3, 'UTC'),
  organization_id UInt64,
  project_id UInt64,
  environment_id UInt64,
  tracking_contract_key LowCardinality(String),
  tracking_contract_version UInt32,
  event_name LowCardinality(String),
  event_type Nullable(String),
  event_id Nullable(String),
  event_time Nullable(DateTime64(3, 'UTC')),
  client_id Nullable(String),
  session_id Nullable(String),
  event_json String
)
ENGINE = ReplacingMergeTree
PARTITION BY toYYYYMM(dda_received_at)
ORDER BY (
  organization_id,
  project_id,
  environment_id,
  dda_event_id
)
SETTINGS non_replicated_deduplication_window = 1000;
"

clickhouse_query \
  --param_writer_password "$DDA_PLATFORM_WRITER_PASSWORD" \
  --query "CREATE USER IF NOT EXISTS dda_platform_writer IDENTIFIED WITH sha256_password BY {writer_password:String}"
clickhouse_query \
  --param_reader_password "$DDA_EXPLORER_READER_PASSWORD" \
  --query "CREATE USER IF NOT EXISTS dda_explorer_reader IDENTIFIED WITH sha256_password BY {reader_password:String}"

clickhouse_query --query "GRANT INSERT, SELECT ON analytics.events TO dda_platform_writer"
clickhouse_query --query "GRANT SELECT ON system.tables TO dda_platform_writer"
clickhouse_query --query "GRANT SHOW TABLES ON analytics.* TO dda_platform_writer"
clickhouse_query --query "GRANT SELECT ON analytics.events TO dda_explorer_reader"
