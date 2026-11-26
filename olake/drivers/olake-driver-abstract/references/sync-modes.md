# Sync modes, backfill and resume

Source: [`drivers/abstract/`](https://github.com/datazip-inc/olake-go/tree/master/drivers/abstract).

## Modes per driver

What each driver offers in `supported_sync_modes`. `discover` lists `cdc` and `strict_cdc` only when the
driver's CDC config is set in `source.json`.

| Driver | `full_refresh` | `incremental` | `cdc` / `strict_cdc` | CDC read |
| --- | --- | --- | --- | --- |
| `postgres` | yes | yes | yes | Logical replication slot, one reader for all streams |
| `mysql` | yes | yes | yes | Binlog, one reader for all streams |
| `mongodb` | yes | yes | yes | Change streams, one per stream, each starts when its backfill ends |
| `mssql` | yes | yes | yes | SQL Server CDC tables, one per stream, each starts when its backfill ends |
| `oracle` | yes | yes | no | |
| `db2` | yes | yes | no | |
| `s3` | yes | yes | no | New or changed files |
| `kafka` | no | no | `strict_cdc` only | Consumer group, parallel readers |

## Choosing a mode

| User wants | Mode | Needs |
| --- | --- | --- |
| One copy, or a small table refreshed each run | `full_refresh` | Nothing. Every run drops and rewrites the table. |
| Regular updates; table has a growing `updated_at` or id; deletes do not matter | `incremental` | `cursor_field`. Deleted rows are never seen. |
| Inserts, updates and deletes, near real time | `cdc` | Source CDC setup ([driver-setup.md](driver-setup.md)). |
| Only changes from now on; history not needed or too large | `strict_cdc` | Source CDC setup. No initial copy. |

Discover's default per stream: `cdc` if supported and configured, else `incremental` (cursor = the
alphabetically first entry in `available_cursor_fields`), else `strict_cdc`, else `full_refresh`.

## Backfill

The initial copy for `full_refresh`, `incremental` and `cdc`. Not for `strict_cdc`.

1. The driver splits the table into chunks (by primary key, `chunk_column`, or a driver-specific
   strategy such as `chunking_strategy` for MongoDB). Chunks are saved in `state.json`.
2. Chunks are read in parallel, up to `max_threads` from `source.json` (default 3 when unset).
3. Each chunk is written and committed on its own. A committed chunk is removed from `state.json`.

Tuning:

- Slow backfill on a big table: raise `max_threads`, as far as the source can serve.
- Uneven chunks or a table without a usable primary key: set `chunk_column` to an indexed column with
  evenly spread values.
- `retry_count` in `source.json` sets retries per chunk.

## Incremental

1. First run: OLake reads the current maximum of `cursor_field`, saves it, then backfills.
2. Later runs: reads rows where `cursor_field` is greater than the saved value, writes them as upserts,
   then saves the new maximum.

- `cursor_field` must only grow. A column that can move backwards loses rows.
- `primary:secondary` uses the second column when the first is null (e.g. `updated_at:created_at`).
- Deletes are not captured. Use `cdc` if they matter.

## CDC

1. Pre-CDC: the driver records the current log position (Postgres LSN, MySQL binlog position,
   MongoDB resume token).
2. Backfill every stream that has not finished its backfill (`strict_cdc` skips this).
3. Read the change log from the saved position. Inserts, updates and deletes are written with
   `_op_type` `c`/`i`, `u` and `d` ([`olake-destination-abstract`](../../../destination/olake-destination-abstract/references/columns.md)).
4. Save the new position in `state.json`.

Each sync reads the log up to the position current at start, then exits. Schedule reruns (cron,
OLake UI) for near real time.

## Reruns and resume

| Situation | What a rerun with `--state` does |
| --- | --- |
| Stopped during backfill | Reads only the chunks still in `state.json`. Committed chunks are skipped (`already committed, skipping`). |
| Backfill done, `incremental` | Reads rows past the saved cursor. |
| Backfill done, `cdc` | Reads the log from the saved position up to the current one, then exits. If the source purged that position (WAL, binlog or oplog retention), the stream must be re-synced. Postgres reports this as `lsn mismatch, please proceed with clear destination`. |
| Rerun without `--state` | Starts over: new backfill of every stream. |
| `cursor_field` or `sync_mode` changed | Run `clear-destination` for the stream, then sync. |
| New stream added | Backfills only the new stream; the others continue. |
