---
name: olake-driver-mysql
description: "Connect MySQL (or MariaDB-compatible MySQL hosts such as RDS, Aurora, Cloud SQL) to OLake as a source (mirrors drivers/mysql): source.json, read grants, and CDC from the binlog (log_bin, binlog_format ROW, binlog_row_image FULL). Use when the source is MySQL and the user wants to run a sync."
metadata:
  parent: olake-driver-abstract
  status: experimental
---

# MySQL source

Image: `olakego/source-mysql:<tag>`. Sync modes: `full_refresh`, `incremental`, `cdc`, `strict_cdc`.
The run (`check`, `discover`, `sync`) is in `olake-protocol`.

## When to use

- The source is MySQL: self-hosted, Docker, RDS, Aurora, Cloud SQL, Azure.
- `check` fails on a MySQL host, or reports failed binlog prerequisites.

## Inputs to collect

Ask only for what is missing. Never echo a password or key back.

| Input | Example | Where it comes from |
| --- | --- | --- |
| `hosts`, `port` | `db.internal`, `3306` | User. From a container, `localhost` is the container: use `host.docker.internal` or the Docker network service name. |
| `database` | `shop` | User |
| `username`, `password` | `olake_user`, `<PASSWORD>` | User or DBA |
| Changes needed: deletes, near real time? | yes / no | User. Yes: CDC. No: `Standalone` with `incremental` or `full_refresh`. |

## Prerequisites

- [ ] Every mode: `GRANT SELECT ON <database>.* TO '<user>'@'%';`
- [ ] CDC only, checked by `check` (`prerequisites` list):
  - `log_bin` = `ON`
  - `binlog_format` = `ROW`
  - `binlog_row_image` = `FULL`
  - `GRANT REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO '<user>'@'%';`
  - Recommended: `binlog_row_metadata` = `FULL`, binlog retention of 7 days or more
    (`binlog_expire_logs_seconds = 604800`).
- [ ] Managed hosts (RDS, Aurora, Cloud SQL) set these in the parameter group or flags, and RDS sets
      retention with `CALL mysql.rds_set_configuration('binlog retention hours', 168);`.

## Steps

1. Write `source.json` in the config folder (example below). Every field:
   [references/config.md](references/config.md).
2. `check` the source, then `discover` (`olake-protocol` steps 2 to 4).
3. In `selected_streams.json`, set the sync mode per stream (`incremental` also needs `cursor_field`).
4. Sync, then rerun with `--state` (`olake-protocol` steps 6 and 7).

```json
{
  "hosts": "<HOST>",
  "port": 3306,
  "database": "<DATABASE>",
  "username": "<USERNAME>",
  "password": "<PASSWORD>",
  "update_method": { "type": "Standalone" },
  "max_threads": 3
}
```

CDC: replace `update_method` with `{ "type": "CDC", "initial_wait_time": 120 }`. If no change arrives
within `initial_wait_time` seconds, the run logs `no records found in given initial wait time, try
increasing it` and ends.

## Verify

- `check` prints `"status":"SUCCEEDED"`; with CDC, every `prerequisites` entry with `"required": true` has `"passed": true`.
- Row count on the destination equals `SELECT COUNT(*) FROM <table>` on the source.
- CDC: insert a row, rerun with `--state`, and find it on the destination with `_op_type` = `c`.

## Common errors

| Error | Cause | Fix |
| --- | --- | --- |
| `required CDC prerequisites not met: binlog_format` (or `log_bin`, `binlog_row_image`, `binlog_access`) | Server setting or grant missing | Set it as in Prerequisites; managed hosts: parameter group, then reboot. |
| `transactions needed after the saved GTID checkpoint have been purged` | Binlog retention shorter than the pause between syncs | `clear-destination` for the streams, then sync; raise retention. |
| `MySQL server UUID changed from ... to ...` | State points at another server (failover, restore) | Reconnect to the original server, or `clear-destination` and re-sync. |
| `connection refused` to `localhost` | `localhost` is the OLake container | `host.docker.internal` or the host IP. |

## Next

- The run, reruns and state: `olake-protocol`.
- Sync modes in general: `olake-driver-abstract`.
- Destination setup: `olake-destination-abstract`, then the destination skill.
- Source column types and what they become: [references/type-mapping.md](references/type-mapping.md).

## Rules

- Changing binlog settings may need a restart on self-hosted servers: the user decides when.
- Use `<PASSWORD>` placeholders; never print secrets.
