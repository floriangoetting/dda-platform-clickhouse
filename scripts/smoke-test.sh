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

compose exec -T clickhouse clickhouse-client \
  --user dda_platform_writer \
  --password "$DDA_PLATFORM_WRITER_PASSWORD" \
  --query "DESCRIBE TABLE analytics.events" \
  | grep -F "event_json" >/dev/null

compose exec -T clickhouse clickhouse-client \
  --user dda_platform_writer \
  --password "$DDA_PLATFORM_WRITER_PASSWORD" \
  --query "INSERT INTO analytics.events
    (dda_schema_version, dda_event_id, dda_batch_id, dda_received_at,
     organization_id, project_id, environment_id, event_schema_id,
     event_schema_version, event_name, event_type, event_id, event_time,
     client_id, session_id, event_json)
    VALUES
    (1, '00000000-0000-4000-8000-000000000001',
     '00000000-0000-4000-8000-000000000002', now64(3),
     1, 1, 1, 1, 1, 'smoke_test', NULL, 'external-1', now64(3),
     'client-1', 'session-1', '{}')"

row_count=$(compose exec -T clickhouse clickhouse-client \
  --user dda_explorer_reader \
  --password "$DDA_EXPLORER_READER_PASSWORD" \
  --query "SELECT count() FROM analytics.events WHERE event_name = 'smoke_test'")

if [ "$row_count" != "1" ]; then
  echo "Reader could not retrieve the writer smoke-test row." >&2
  exit 1
fi

echo "Writer and reader smoke test passed."
