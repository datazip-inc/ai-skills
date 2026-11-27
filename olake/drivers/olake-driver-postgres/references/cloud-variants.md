# Postgres host variants

How each host sets the [CDC prerequisites](prerequisites.md#cdc). Publication, slot and replica identity
SQL is the same everywhere. Full guides: [olake.io Postgres setup](https://olake.io/docs/connectors/postgres).

| Host | Turn on logical WAL | Replication privilege | Restart | SSL |
| --- | --- | --- | --- | --- |
| Self-hosted / VM | `wal_level = logical` in `postgresql.conf` | `ALTER ROLE ... WITH REPLICATION` | Yes | Per `pg_hba.conf` |
| Docker (local) | `command: postgres -c wal_level=logical -c wal_sender_timeout=0` | Image superuser has it | Recreate container | `disable` |
| Amazon RDS | Custom DB parameter group: `rds.logical_replication = 1` | `GRANT rds_replication TO olake_user;` | Reboot instance | `require` |
| Aurora PostgreSQL | Custom **cluster** parameter group: `rds.logical_replication = 1` | `GRANT rds_replication TO olake_user;` | Reboot writer | `require` |
| Azure Flexible Server | Server parameters: `wal_level = logical` | `ALTER ROLE ... WITH REPLICATION` (run as the admin, a member of `azure_pg_admin`) | Yes (portal prompts) | `require` |
| Google Cloud SQL | Database flag `cloudsql.logical_decoding = on` | `ALTER ROLE ... WITH REPLICATION` (run as `postgres`) | Yes | `require` or Cloud SQL Proxy |
| Supabase | Already `logical` | `postgres` user has it | No | `require` |

Set `wal_sender_timeout = 0` the same way as the WAL setting (parameter group, server parameter, flag).

## Amazon RDS and Aurora

- The default parameter group cannot be edited: create one, attach it, then reboot.
- After reboot: `SHOW rds.logical_replication;` is `on` and `SHOW wal_level;` is `logical`.
- RDS read replicas accept `rds.logical_replication` only on Postgres 16+. Aurora readers never do:
  use the writer endpoint for CDC.
- `check` accepts `rds_replication` membership for `replication_privilege`.
- Security group: inbound 5432 from OLake's IP or VPC CIDR.

## Azure Database for PostgreSQL (Flexible Server)

- `ssl.mode` must be `require` or stricter. With `disable` the connection fails with
  `no pg_hba.conf entry for host ... no encryption (SQLSTATE 28000)`. (The olake.io page suggests
  `allow`; that value is not in the spec and fails validation. Use `require`.)
- Networking: add OLake's IP to the firewall rules, or use private access from the same VNet.

## Google Cloud SQL

- Flags are set under *Edit → Flags*. `cloudsql.logical_decoding` restarts the instance.
- Authorize OLake's IP under *Connections → Networking*, or run the Cloud SQL Auth Proxy next to OLake
  and point `host` at it.

## Supabase

| Connection | Use for |
| --- | --- |
| Direct (`db.<ref>.supabase.co:5432`) | CDC. Replication slots work only here. IPv6 only unless the IPv4 add-on is on. |
| Session pooler (`...pooler.supabase.com:5432`) | `full_refresh` / `incremental` from IPv4-only networks |
| Transaction pooler (`:6543`) | `full_refresh` / `incremental` |

- Docker is IPv4 only by default. For the direct connection, enable IPv6 in Docker Engine settings
  (`"ipv6": true`) and restart Docker. Check the network with `curl -6 https://ifconfig.co/ip`.
- Supabase enables row-level security on many tables: give the OLake user `BYPASSRLS`, or the sync
  returns zero rows.

## Local Docker

```yaml
services:
  postgres:
    image: postgres:16
    command: postgres -c wal_level=logical -c max_wal_senders=10 -c max_replication_slots=10 -c wal_sender_timeout=0
    environment:
      POSTGRES_USER: main
      POSTGRES_PASSWORD: <PASSWORD>
      POSTGRES_DB: main
    ports: ["5432:5432"]
```

From an OLake container on the same machine, `host` is `host.docker.internal` (Docker Desktop) or the
service name when both run on one Docker network (`--network <NETWORK>`).
