---
name: olake-driver-postgres
description: "Connect PostgreSQL to OLake as a source (mirrors drivers/postgres): source.json, read grants, CDC through logical replication with pgoutput (wal_level, replication slot, publication, REPLICA IDENTITY), host variants (RDS, Aurora, Azure, Cloud SQL, Supabase, local Docker), ctid chunked backfill, type mapping and Postgres errors. Use when the source is Postgres or a Postgres-compatible managed service, or on errors about wal_level, replication slots, publications, LSN, pg_hba.conf or SQLSTATE codes."
metadata:
  parent: olake-driver-abstract
  status: experimental
---

# Postgres source

Image: `olakego/source-postgres:<tag>`. Postgres 10 or later. Sync modes: `full_refresh`,
`incremental`, `cdc`, `strict_cdc`. The run (`check`, `discover`, `sync`) is in `olake-protocol`;
how the modes behave in general is in `olake-driver-abstract`.

## When to use

- The source is Postgres: self-hosted, Docker, RDS, Aurora, Azure Flexible Server, Cloud SQL, Supabase.
- `check` fails on a Postgres host, or reports failed CDC prerequisites (`wal_level`,
  `replication_privilege`, `replication_slot`, `publication`, `wal_sender_timeout`).
- A CDC sync fails with `lsn mismatch`, `publication ... does not exist` or `LSN not updated`.
- Not covered: the destination side → `olake-destination-abstract`; general sync-mode choice →
  `olake-driver-abstract`.

## Inputs to collect

Ask only for what is missing. Never echo the password back.

| Input | Example | Where it comes from |
| --- | --- | --- |
| Host type | RDS, Aurora, Azure, Cloud SQL, Supabase, self-hosted, Docker | User |
| `host`, `port` | `db.internal`, `5432` | User. From a container, `localhost` is the container: use `host.docker.internal` or the Docker network service name. |
| `database` | `shop` | User. One database per source; slots and publications are per database. |
| `username`, `password` | `olake_user`, `<PASSWORD>` | User or DBA |
| Schemas to sync | `["public"]` | User. Empty means every non-system schema. |
| Changes needed: deletes, near real time? | yes / no | User. Yes → CDC. No → `Standalone` with `incremental` or `full_refresh`. |
| `replication_slot`, `publication` (CDC) | `olake_slot`, `olake_pub` | DBA creates them. One pair per OLake job. |
| SSL / SSH tunnel | `require`, bastion host | User. Managed clouds usually need `ssl.mode` `require`. |

## Prerequisites

- [ ] Every mode: the user can `CONNECT` to the database and `SELECT` the tables, and the host
      accepts the connection (`pg_hba.conf`, firewall, security group).
      [references/prerequisites.md](references/prerequisites.md#read-access)
- [ ] CDC only: `wal_level=logical`, a user with `REPLICATION` (RDS/Aurora: `rds_replication`),
      a publication that holds every synced table, a `pgoutput` slot in the same database,
      `wal_sender_timeout=0`. [references/prerequisites.md](references/prerequisites.md#cdc)
- [ ] Managed host: apply the host's way of setting these.
      [references/cloud-variants.md](references/cloud-variants.md)
- [ ] Run [scripts/verify_source.sh](scripts/verify_source.sh) (read-only). It checks what `check`
      does not: read grants, publication coverage, replica identity, partitioned tables.

## Steps

1. Pick the update method. CDC needs the settings above; `Standalone` needs only read access.
2. CDC: apply the settings from [references/prerequisites.md](references/prerequisites.md#cdc), or
   send the SQL to the DBA. `wal_level` needs a restart: confirm with the user first.
3. Run the verify script and fix every `FAIL`:
   ```bash
   PGHOST=<HOST> PGPORT=5432 PGDATABASE=<DATABASE> PGUSER=<USERNAME> PGPASSWORD=<PASSWORD> \
   OLAKE_SCHEMAS=public OLAKE_SLOT=olake_slot OLAKE_PUBLICATION=olake_pub \
     bash scripts/verify_source.sh
   ```
   Leave out `OLAKE_SLOT` and `OLAKE_PUBLICATION` for `Standalone`.
4. Write `source.json`. Standalone:
   ```json
   {
     "host": "<HOST>",
     "port": 5432,
     "database": "<DATABASE>",
     "username": "<USERNAME>",
     "password": "<PASSWORD>",
     "schemas": ["public"],
     "ssl": { "mode": "disable" },
     "update_method": { "type": "Standalone" },
     "max_threads": 3
   }
   ```
   CDC: replace `update_method` with
   `{ "type": "CDC", "replication_slot": "olake_slot", "publication": "olake_pub", "initial_wait_time": 600 }`.
   Every field: [references/config.md](references/config.md).
5. `check` the source (`olake-protocol` step 2). With CDC, read the `prerequisites` list and fix every
   required entry that failed. A `current_value` of `unavailable` means the user cannot read the setting.
6. `discover`. Then in `selected_streams.json`:
   - `incremental`: set `cursor_field` to a growing column (`updated_at`, a serial id).
   - Large table: leave `chunk_column` empty (ctid chunking). Set it only to a numeric primary key
     column. [references/sync-modes.md](references/sync-modes.md#backfill)
7. Sync and rerun with `--state` (`olake-protocol` steps 6 and 7).

## Verify

- `check` prints `"status":"SUCCEEDED"`; with CDC, every `prerequisites` entry with `"required": true`
  has `"passed": true`.
- Sync log: `Connected to Postgres server_version_num=<n>`, then `Found CDC Configuration` (CDC) or
  `Standard Replication is selected` (Standalone).
- Row count on the destination equals `SELECT COUNT(*) FROM <schema>.<table>` on the source.
- CDC: insert a row, rerun with `--state`, and find it on the destination with `_op_type` = `c`.
  Delete a row, rerun, and find `_op_type` = `d`.

## Common errors

| Error (verbatim) | Cause | Fix |
| --- | --- | --- |
| `no pg_hba.conf entry for host "<ip>", user "<user>", database "<db>", no encryption (SQLSTATE 28000)` | Host requires SSL, or `pg_hba.conf` has no line for OLake's IP | Set `"ssl": {"mode": "require"}`; else add a `pg_hba.conf` entry for OLake's IP. |
| `password authentication failed for user` (SQLSTATE `28P01`) | Wrong user or password | Ask the user to re-enter the password in `source.json`. |
| `publication "<pub>" does not exist; please create it with: CREATE PUBLICATION ...` | No publication with that name in this database | Create it ([prerequisites.md](references/prerequisites.md#cdc)), or fix the name. |
| `the following tables are selected in streams.json but are NOT tracked by publication` | A synced table is not in the publication | `ALTER PUBLICATION <pub> ADD TABLE <schema>.<table>;` |
| `lsn mismatch, please proceed with clear destination` | The slot moved past the LSN saved in `state.json` (slot recreated, reused by another job, or WAL lost) | Confirm with the user, then `clear-destination` and a fresh sync. Give each job its own slot. |
| `LSN not updated after 5 minutes` | `wal_sender_timeout` closed the replication connection | Set `wal_sender_timeout = 0` and reload. |

Full list, SQLSTATE meanings and data issues (null columns on deletes, TOAST):
[references/troubleshooting.md](references/troubleshooting.md)

## Next

- Destination setup: `olake-destination-abstract`, then the destination skill.
- Run, reruns and state: `olake-protocol`.
- Source column types and what they become: [references/type-mapping.md](references/type-mapping.md).

## Rules

- Never drop or recreate a replication slot, or drop a publication, without the user's explicit yes:
  it loses changes and forces a full re-sync.
- Never share a slot or publication between two OLake jobs.
- A slot that nobody reads keeps WAL forever and can fill the disk. When a CDC job is removed, tell the
  user to drop its slot.
- Changing `wal_level` restarts the database: the user decides when.
- Use `<PASSWORD>` placeholders; never print secrets. The verify script reads `PGPASSWORD` from the
  environment and never prints it.
