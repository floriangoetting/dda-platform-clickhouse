# DDA Platform ClickHouse

Versioned deployment kit for a customer-owned ClickHouse destination used by the Drag & Drop Analytics Platform.

The kit creates the `dda_native_v1` event table and two purpose-specific database users:

- `dda_platform_writer` for Platform delivery and connection tests
- `dda_explorer_reader` for read-only Explorer access

Drag & Drop Analytics stores the destination credentials in encrypted form and delivers accepted events to this database. The ClickHouse server, storage, backups, retention, DNS, TLS, firewall rules and upgrades remain under the customer's control.

## Requirements

- Linux server with Docker Engine and Docker Compose
- public hostname such as `clickhouse.example.com`
- valid DNS record for that hostname
- an existing HTTPS reverse proxy, or free ports 80 and 443 for the optional Caddy profile
- persistent storage and a tested backup strategy

The Platform accepts public HTTPS endpoints in production. Do not expose the ClickHouse HTTP port `8123` directly. This kit binds it to `127.0.0.1:18123` by default and expects HTTPS to terminate at a reverse proxy.

## Quick start

Clone the repository and create the local environment file:

```bash
git clone https://github.com/floriangoetting/dda-platform-clickhouse.git
cd dda-platform-clickhouse
cp .env.example .env
```

Set `CLICKHOUSE_PUBLIC_HOST` and replace all three example passwords with independent random values. The `.env` file is ignored by Git.

Start ClickHouse:

```bash
docker compose up -d clickhouse
docker compose ps
docker compose logs --tail=100 clickhouse
```

The bootstrap creates `analytics.events` and the two restricted users when the data volume is initialized for the first time.

### Resource-conscious system logging

The deployment mounts `config.d/resource-conscious-logging.xml` to keep
ClickHouse diagnostics useful without allowing system logs to dominate a small
destination host. It changes the server file log from `trace` to `information`,
rotates it at 50 MB with three retained files, samples the metric log every ten
seconds and applies short TTLs to high-volume `system.*_log` tables. Query and
part logs remain available for seven days, errors for fourteen days and the
highest-volume diagnostic logs for one to three days.

These limits affect only ClickHouse diagnostic logs. They do not add a TTL to
`analytics.events` or delete Platform event data. Operators that require a
longer diagnostic history should export logs to their monitoring system or
adapt the mounted configuration deliberately while retaining a bounded policy.

## Publish the HTTPS endpoint

Choose exactly one reverse-proxy option.

### Standalone Caddy

Use the included profile only when no other service owns ports 80 and 443. Caddy obtains and renews the TLS certificate automatically:

```bash
docker compose --profile standalone-caddy up -d
docker compose logs --tail=100 clickhouse caddy
```

The active configuration is [`proxy/Caddyfile.example`](proxy/Caddyfile.example).

### Existing Nginx

Adapt [`proxy/nginx.conf.example`](proxy/nginx.conf.example) to the hostname, certificate paths and local port. Validate the complete Nginx configuration before reloading it:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

### Existing Apache HTTP Server

Adapt [`proxy/apache-vhost.conf.example`](proxy/apache-vhost.conf.example). It requires `mod_ssl`, `mod_proxy` and `mod_proxy_http`:

```bash
sudo apachectl configtest
sudo systemctl reload apache2
```

All supplied proxy examples accept only `POST`, preserve Basic Authentication, and forward requests to ClickHouse. Another proxy is supported if it preserves the `Authorization` header, query string and request body.

## Verify the public endpoint

The following probe asks for the writer password interactively and validates the real TLS certificate:

```bash
curl --fail --request POST \
  --user dda_platform_writer \
  --data-binary 'SELECT 1' \
  https://clickhouse.example.com
```

Do not use `--insecure` for this check.

## Connect Drag & Drop Analytics

Open the Platform project, select the environment, and configure its ClickHouse destination with these values:

| DDA field | Value |
| --- | --- |
| HTTPS endpoint | `https://clickhouse.example.com` |
| Database | `analytics` |
| Events table | `events` |
| Writer username | `dda_platform_writer` |
| Writer password | `DDA_PLATFORM_WRITER_PASSWORD` from `.env` |
| Explorer access | enable when the table should be available in Explorer |
| Explorer username | `dda_explorer_reader` |
| Explorer password | `DDA_EXPLORER_READER_PASSWORD` from `.env` |

Run **Test connection** after saving. DDA verifies reachability, credentials, all `dda_native_v1` columns, the MergeTree deduplication contract and, when enabled, the separate Explorer reader.

Never enter the bootstrap admin account in DDA.

## Database roles

| User | Intended use | Grants |
| --- | --- | --- |
| value of `CLICKHOUSE_ADMIN_USER` | bootstrap and maintenance | administrative; never store in DDA |
| `dda_platform_writer` | Platform delivery and connection test | `INSERT` and contract-validation reads only |
| `dda_explorer_reader` | Explorer queries | `SELECT` on `analytics.events` only |

Writer and reader passwords must differ. Rotate credentials deliberately in ClickHouse and DDA; changing `.env` alone does not modify users in an existing data volume.

## Data contract

The table implements `dda_native_v1`. It contains stable Platform scope and
delivery metadata, the internal project-schema ID and producer-selected schema
version, mapped core event fields, and the schema-allowlisted event as canonical
JSON in `event_json`. Unknown fields are discarded by DDA before delivery.

The bootstrap is idempotent for a new volume, but it is not a schema migration system. Future contract changes will be published as repository releases with explicit upgrade notes. Pin production deployments to a reviewed tag or commit instead of following the default branch automatically.

## Operations and responsibility

Before production use, define and test:

- storage sizing and monitoring
- retention or ClickHouse TTL rules
- encrypted backups and restore drills
- ClickHouse and container-image upgrades
- firewall policy and credential rotation
- deletion procedures for privacy and retention requests

The supplied system-log limits are operational defaults for the ClickHouse
service itself. Product-event retention for `analytics.events` remains an
explicit operator decision and is not configured by this kit.

DDA can validate the destination contract and report delivery failures. It cannot manage the customer's server, DNS, backups, retention or network policy.

## Validation

Validate scripts and the resolved Compose configuration without starting services:

```bash
./scripts/validate.sh
```

Run an isolated local integration test that starts a temporary ClickHouse project, bootstraps the schema, inserts through the writer and reads through the Explorer user:

```bash
./scripts/smoke-test.sh
```

The smoke-test project and its temporary volumes are removed automatically.

## License

Licensed under the Apache License, Version 2.0. See [`LICENSE`](LICENSE).
