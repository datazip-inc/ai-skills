# Postgres sync modes

What Postgres does on top of the shared behaviour in
[`olake-driver-abstract`](../../olake-driver-abstract/references/sync-modes.md).
Source: [`drivers/postgres/internal/`](https://github.com/datazip-inc/olake/tree/v1.1.2/drivers/postgres/internal).

| Mode | Needs |
| --- | --- |
| `full_refresh` | `SELECT` |
| `incremental` | `SELECT`, a `cursor_field` that only grows |
| `cdc`, `strict_cdc` | `update_method.type` = `CDC` and the [CDC prerequisites](prerequisites.md#cdc) |

`discover` lists `cdc` and `strict_cdc` only when `update_method` is `CDC`.

## Backfill

Default (no `chunk_column`): **ctid ranges**. The driver reads the table size from `pg_class`, splits
the heap into page ranges, and reads each range with `WHERE ctid >= ... AND ctid < ...`.

- Works on tables without a primary key.
- Partitioned tables are chunked per partition. `all partitions are empty for stream[...]` (warning)
  means there is nothing to copy.
- The record total in `stats.json` starts from `pg_class.reltuples`, an estimate. Run `ANALYZE` on the
  table if the estimate is far off; the synced rows are not affected.

With `chunk_column` set in `selected_streams.json`:

- It must be a primary key column, or the sync fails with `provided split column is not a primary key`.
- Integer and float columns split evenly between min and max. Other types split by querying the next
  chunk end, which is slower.
- UUID columns are not supported as `chunk_column`. Leave it empty.

Parallelism is `max_threads` (default 3). Each thread holds one connection, so keep it below the
server's free connections (`too_many_connections`, SQLSTATE `53300`).

## Incremental

- `cursor_field` from `available_cursor_fields`. Good: `updated_at` maintained by a trigger or the app,
  a `bigserial` id for insert-only tables.
- `updated_at:created_at` falls back to `created_at` when `updated_at` is null.
- Deletes are never seen. Use CDC when they matter.

## CDC

1. Setup validates the publication: it must exist and hold every selected stream, else the sync stops
   before reading.
2. Pre-CDC reads the slot's `confirmed_flush_lsn` and compares it with the LSN in `state.json`. If they
   differ, the sync stops with `lsn mismatch, please proceed with clear destination`.
3. Backfill runs for streams that have not finished it.
4. One replication connection reads all streams from the slot up to the LSN current at start, then
   confirms the LSN to the slot so Postgres can free WAL.

When the slot is already at the current WAL position, the run ends at once
(`finishing sync, reached wal position: <lsn>`).

`initial_wait_time` (seconds): how long the reader waits for the first message while catching up. If
nothing arrives in time the sync **fails** with
`no records found in given initial wait time, try increasing it or do full load`. That happens when
Postgres must decode a lot of WAL first (bulk loads, busy tables outside the publication). Raise it
(600–3600) on such servers. Minimum 120; a lower or missing value logs
`initial_wait_time <n> is below the minimum of 120 seconds; using default 10800` and uses 10800.

### What lands on the destination

| Source change | Destination row |
| --- | --- |
| `INSERT` | `_op_type` = `c` |
| `UPDATE` | `_op_type` = `u`. Unchanged TOAST columns (large text, json) arrive as null unless the table has `REPLICA IDENTITY FULL`; the log warns `table[<t>] replica identity is not FULL, unchanged TOAST column values may be lost`. |
| `DELETE` | `_op_type` = `d`. Only key columns are filled unless the table has `REPLICA IDENTITY FULL`. |
| `TRUNCATE` | Ignored: rows stay on the destination. |

### Reruns

| Situation | Result |
| --- | --- |
| Rerun with `--state` | Reads from the saved LSN. |
| Slot dropped and recreated | `lsn mismatch`. With the user's yes: `clear-destination`, then a full sync. |
| Two jobs on one slot | Each confirms LSNs the other has not read: silent data loss, then `lsn mismatch`. Give each job its own slot and publication. |
| Job paused for days | The slot holds all WAL since the last run. Watch disk; `max_slot_wal_keep_size` caps it but then invalidates the slot. |
