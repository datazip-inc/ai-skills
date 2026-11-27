---
name: olake-driver-db2
description: "Connect IBM Db2 (LUW) to OLake as a source (mirrors drivers/db2): source.json, read grants, full_refresh and incremental sync (no CDC at this version). Use when the source is Db2 and the user wants to run a sync."
metadata:
  parent: olake-driver-abstract
  status: experimental
---

# Db2 source

Image: `olakego/source-db2:<tag>`. Sync modes: `full_refresh`, `incremental`. No CDC at this version:
deletes are not captured. The run (`check`, `discover`, `sync`) is in `olake-protocol`.

## When to use

- The source is Db2 for Linux, Unix and Windows.
- `check` fails on a Db2 host.

## Inputs to collect

Ask only for what is missing. Never echo a password or key back.

| Input | Example | Where it comes from |
| --- | --- | --- |
| `host`, `port` | `db2.internal`, `50000` | User. From a container, `localhost` is the container: use `host.docker.internal` or the Docker network service name. |
| `database` | `SAMPLE` | User |
| `username`, `password` | `db2inst1`, `<PASSWORD>` | User or DBA |

## Prerequisites

- [ ] `GRANT CONNECT ON DATABASE TO USER <user>;` and `SELECT` on every table to sync.
- [ ] The Db2 port is reachable from where OLake runs.
- [ ] Table statistics exist for every synced table. The backfill splits tables from catalog stats;
      without them the sync fails with `stats not populated for table[<SCHEMA>.<TABLE>]`. A DBA runs,
      per table: `RUNSTATS ON TABLE <SCHEMA>.<TABLE> AND INDEXES ALL;`
- [ ] Apple Silicon: `olakego/source-db2` is amd64 only. Add `--platform linux/amd64` to every
      `docker run`; it runs under emulation.

## Steps

1. Write `source.json` in the config folder (example below). Every field:
   [references/config.md](references/config.md).
2. `check` the source, then `discover` (`olake-protocol` steps 2 to 4).
3. In `selected_streams.json`, set the sync mode per stream (`incremental` also needs `cursor_field`, a column that only grows).
4. Sync, then rerun with `--state` (`olake-protocol` steps 6 and 7).

```json
{
  "host": "<HOST>",
  "port": 50000,
  "database": "<DATABASE>",
  "username": "<USERNAME>",
  "password": "<PASSWORD>",
  "max_threads": 3
}
```

## Verify

- `check` prints `"status":"SUCCEEDED"`.
- Row count on the destination equals `SELECT COUNT(*) FROM <schema>.<table>` on the source.

## Common errors

| Error | Cause | Fix |
| --- | --- | --- |
| `stats not populated for table[<SCHEMA>.<TABLE>]` | No catalog statistics | `RUNSTATS ON TABLE <SCHEMA>.<TABLE> AND INDEXES ALL;`, then sync. |
| `exec format error` or very slow start on Apple Silicon | amd64-only image | `--platform linux/amd64` on every `docker run`. |
| `SQL30082N` security processing failed | Wrong user or password | Check the credentials with `db2 connect`. |

## Next

- The run, reruns and state: `olake-protocol`.
- Sync modes in general: `olake-driver-abstract`.
- Destination setup: `olake-destination-abstract`, then the destination skill.
- Source column types and what they become: [references/type-mapping.md](references/type-mapping.md).

## Rules

- Use `<PASSWORD>` placeholders; never print secrets.
