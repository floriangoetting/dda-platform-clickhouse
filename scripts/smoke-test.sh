#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repository_root"

smoke_project="dda-clickhouse-smoke-$$"
compose() {
  docker compose -p "$smoke_project" --env-file .env.example "$@"
}
cleanup() {
  compose down --volumes --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

set -a
. ./.env.example
set +a

compose up -d clickhouse

attempt=0
until [ "$(compose ps --format json clickhouse | grep -c '"Health":"healthy"' || true)" -gt 0 ]; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 36 ]; then
    compose logs clickhouse
    echo "ClickHouse did not become healthy." >&2
    exit 1
  fi
  sleep 5
done

assert_config_value() {
  key=$1
  expected=$2
  actual=$(compose exec -T clickhouse clickhouse extract-from-config \
    --config-file=/etc/clickhouse-server/config.xml \
    --key="$key")

  if [ "$actual" != "$expected" ]; then
    echo "Unexpected ClickHouse config value for $key: $actual" >&2
    exit 1
  fi
}

assert_config_value logger.level information
assert_config_value logger.size 50M
assert_config_value logger.count 3
assert_config_value trace_log.ttl "event_date + INTERVAL 1 DAY DELETE"
assert_config_value query_log.ttl "event_date + INTERVAL 7 DAY DELETE"
assert_config_value text_log.level information
assert_config_value metric_log.collect_interval_milliseconds 10000

compose exec -T clickhouse clickhouse-client \
  --user "$DDA_PLATFORM_WRITER_USER" \
  --password "$DDA_PLATFORM_WRITER_PASSWORD" \
  --query "DESCRIBE TABLE \`$DDA_CLICKHOUSE_DATABASE\`.\`$DDA_CLICKHOUSE_EVENTS_TABLE\`" \
  | grep -F "event_json" >/dev/null

compose exec -T clickhouse clickhouse-client \
  --user "$DDA_PLATFORM_WRITER_USER" \
  --password "$DDA_PLATFORM_WRITER_PASSWORD" \
  --query "INSERT INTO \`$DDA_CLICKHOUSE_DATABASE\`.\`$DDA_CLICKHOUSE_EVENTS_TABLE\`
    (dda_schema_version, dda_event_id, dda_received_at,
     event_schema_version, event_name, event_type, event_id, event_time,
     client_id, session_id, event_json)
    VALUES
    (2, '00000000-0000-4000-8000-000000000001',
     now64(3), 1, 'smoke_test', NULL, 'external-1', now64(3),
     'client-1', 'session-1', '{}')"

row_count=$(compose exec -T clickhouse clickhouse-client \
  --user "$DDA_EXPLORER_READER_USER" \
  --password "$DDA_EXPLORER_READER_PASSWORD" \
  --query "SELECT count() FROM \`$DDA_CLICKHOUSE_DATABASE\`.\`$DDA_CLICKHOUSE_EVENTS_TABLE\` WHERE event_name = 'smoke_test'")

if [ "$row_count" != "1" ]; then
  echo "Reader could not retrieve the writer smoke-test row." >&2
  exit 1
fi

echo "Writer and reader smoke test passed."
