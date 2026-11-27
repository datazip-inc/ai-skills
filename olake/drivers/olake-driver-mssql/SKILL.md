---
name: olake-driver-mssql
description: "Connect SQL Server to OLake (self-hosted, Azure SQL, RDS): source.json, grants, CDC through SQL Server change data capture (enabled per database and table, SQL Server Agent running). Use when the source is SQL Server, or on CDC, cdc_jobs or Agent errors."
metadata:
  parent: olake-driver-abstract
  status: experimental
---

# SQL Server source

Image: `olakego/source-mssql:<tag>`. Sync modes: `full_refresh`, `incremental`, `cdc`, `strict_cdc`.
The run (`check`, `discover`, `sync`) is in `olake-protocol`.

## When to use

- The source is SQL Server: self-hosted, Docker, Azure SQL, RDS.
- `check` fails on a SQL Server host, or reports failed CDC prerequisites.

## Inputs to collect

Ask only for what is missing. Never echo a password or key back.

| Input | Example | Where it comes from |
| --- | --- | --- |
| `host`, `port` | `sql.internal`, `1433` | User. From a container, `localhost` is the container: use `host.docker.internal` or the Docker network service name. |
| `database` | `shop` | User |
| `username`, `password` | `olake_user`, `<PASSWORD>` | User or DBA |
| `ssl.mode` | `disable` or `require` | User. Azure SQL needs `require`. |
| Changes needed: deletes, near real time? | yes / no | User. Yes: CDC. |

## Prerequisites

- [ ] Every mode: `SELECT` on the tables to sync.
- [ ] CDC only (a `db_owner` or sysadmin runs these):
  ```sql
  EXEC sys.sp_cdc_enable_db;
  EXEC sys.sp_cdc_enable_table @source_schema = N'dbo', @source_name = N'<TABLE>', @role_name = NULL;
  ```
  - One `sp_cdc_enable_table` per synced table, else the sync fails with
    `CDC is not enabled for stream <schema>.<table>`.
  - SQL Server Agent runs, so the capture job runs. RDS: use
    `msdb.dbo.rds_cdc_enable_db '<DATABASE>'` instead of `sp_cdc_enable_db`.
  - The OLake user can read the capture job, else `check` fails with
    `required CDC prerequisites not met: cdc_capture_job` (`no SELECT on msdb.dbo.cdc_jobs`):
    ```sql
    USE msdb;
    CREATE USER <USER> FOR LOGIN <LOGIN>;
    GRANT SELECT ON msdb.dbo.cdc_jobs TO <USER>;
    ```
  - Recommended: `GRANT VIEW DATABASE STATE TO <user>;`.

## Steps

1. Write `source.json` in the config folder (example below). Every field:
   [references/config.md](references/config.md).
2. `check` the source, then `discover` (`olake-protocol` steps 2 to 4).
3. In `selected_streams.json`, set the sync mode per stream (`incremental` also needs `cursor_field`).
   With CDC enabled, discover also lists `dbo.systranschemas` (a CDC system table). Remove it: the
   sync fails with `CDC is not enabled for stream dbo.systranschemas`.
4. Sync, then rerun with `--state` (`olake-protocol` steps 6 and 7).

```json
{
  "host": "<HOST>",
  "port": 1433,
  "database": "<DATABASE>",
  "username": "<USERNAME>",
  "password": "<PASSWORD>",
  "ssl": { "mode": "disable" },
  "update_method": { "type": "Standalone" },
  "max_threads": 3
}
```

CDC: replace `update_method` with `{ "type": "CDC" }`.

## Verify

- `check` prints `"status":"SUCCEEDED"`; with CDC, every `prerequisites` entry with `"required": true` has `"passed": true`.
- Row count on the destination equals `SELECT COUNT(*) FROM <schema>.<table>` on the source.
- CDC: insert a row, rerun with `--state`, and find it on the destination with `_op_type` = `c`.

## Common errors

| Error | Cause | Fix |
| --- | --- | --- |
| `required CDC prerequisites not met: cdc_capture_job` | No `SELECT` on `msdb.dbo.cdc_jobs`, or SQL Server Agent stopped | Grant as in Prerequisites; start the Agent. |
| `CDC is not enabled for stream <schema>.<table>` | Table without `sp_cdc_enable_table`, or `dbo.systranschemas` selected | Enable CDC on the table, or remove the stream (Step 3). |
| `Login failed for user '<USER>'` | Wrong login or password, or SQL authentication off | Check the login; enable mixed-mode authentication. |

## Next

- The run, reruns and state: `olake-protocol`.
- Sync modes in general: `olake-driver-abstract`.
- Destination setup: `olake-destination-abstract`, then the destination skill.
- Source column types and what they become: [references/type-mapping.md](references/type-mapping.md).

## Rules

- Enabling CDC changes the database (change tables, Agent jobs): confirm with the user or DBA first.
- Use `<PASSWORD>` placeholders; never print secrets.
