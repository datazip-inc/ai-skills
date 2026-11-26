---
name: olake-destination-abstract
description: "Writer behaviour shared by OLake destinations (mirrors destination/): Iceberg vs Parquet, normalization, partition_regex, append vs upsert, delete formats (eq, pos, dv) and target query engines, the _olake_* columns, schema evolution, and writer errors. Use when the user configures destination.json, sets normalization, partitioning, append_mode or update_type in selected_streams.json, asks why a table has duplicates or a data column, or a sync fails while writing."
metadata:
  parent: olake-protocol
  status: experimental
---

# OLake destinations: how data is written

What both writers (`iceberg`, `parquet`) do the same way, and the per-stream settings that control it.
The run itself is in `olake-protocol`.

## When to use

- Write `destination.json` for Iceberg or Parquet.
- Set `normalization`, `partition_regex`, `append_mode` or `update_type` per stream.
- The user asks about `_olake_id`, `_op_type`, duplicates, deletes or a single `data` column.
- `sync` fails while writing, or the table cannot be read by the user's query engine.
- Not covered: sync modes, cursors, CDC: load `olake-driver-abstract`.

## Inputs to collect

| Input | Example | Where it comes from |
| --- | --- | --- |
| Destination type | `iceberg` or `parquet` | User |
| Catalog and storage (Iceberg) | REST on MinIO, Glue on S3 | User |
| Path and storage (Parquet) | `s3://bucket/prefix`, local folder | User |
| Query engines that read the tables | `spark,trino` | User. Decides the delete format. |
| Upserts or append-only | upsert | User |
| Partition columns | `created_at` by day | User |

## Prerequisites

- [ ] Catalog and storage are reachable from the container (not `localhost`) and the credentials can
      create namespaces, tables and files.
- [ ] `destination.json` written from the schema:
      `docker run --rm olakego/source-<source>:<tag> spec --destination-type iceberg` (or `parquet`).
      Field guide: [references/destination-config.md](references/destination-config.md).

## Steps

1. Write `destination.json` and run `check --destination` (`olake-protocol` step 3).
2. Run `discover` with `--destination`, and with `--target-query-engines <list>` when the user named
   engines. This sets `available_update_types` per stream. Pass the same engines on every `discover`.
3. Per stream in `selected_streams.json`, set:
   - `normalization`: `true` for columns per top-level field (default for SQL sources); `false` keeps the
     row as one JSON `data` column.
   - `partition_regex`: see [references/partitioning.md](references/partitioning.md).
   - `append_mode`: `true` writes every change as a new row (default for `s3`, `kafka`); `false` upserts.
   - `update_type` (Iceberg upserts only): `eq`, `pos` or `dv`, from `available_update_types`.
     Guide: [references/upserts-and-deletes.md](references/upserts-and-deletes.md).
4. Sync.

## Verify

- The table exists in namespace `destination_database` (from the streams file, else `iceberg_db`,
  else the source namespace). Count rows with the user's engine and compare with the source.
- With upserts, `SELECT _olake_id, COUNT(*) ... GROUP BY 1 HAVING COUNT(*) > 1` returns no rows.
- Column meanings: [references/columns.md](references/columns.md).

## Common errors

| Error (verbatim) | Cause | Fix |
| --- | --- | --- |
| `invalid destination type has been passed [<type>]` | Wrong `type` in `destination.json` | Use `ICEBERG` or `PARQUET`. |
| `no matches found for partition regex: <pattern>` | Iceberg `partition_regex` not in `/{column, transform}` form | Fix the pattern ([references/partitioning.md](references/partitioning.md)). |
| `update mode "<x>" is not supported by the target query engines or the destination catalog; supported update modes: [...]` | `update_type` not readable by the chosen engines or catalog | Pick one from the list, or set `append_mode: true`. |
| `Stream <name> update mode <x> is not supported ...; cleared, choose one of [...] or append mode` (warning) | A rerun of `discover` dropped the old delete format | Set `update_type` again before syncing. |
| `failed to test destination: ...` | Catalog or storage unreachable, or bad credentials | Fix the endpoint (not `localhost`) or credentials, then `check --destination`. |

More, by error class: [references/writer-errors.md](references/writer-errors.md)

## Next

- Catalog and storage specifics: `olake-destination-iceberg` (Parquet: writer docs on olake.io until
  its skill exists).
- Sync modes and CDC: `olake-driver-abstract`.

## Rules

- Tell the user before changing `normalization`, `partition_regex`, `append_mode` or `update_type` on a
  synced stream: the stream then needs `clear-destination` and a full re-sync, and switching delete
  formats can recreate the table.
- Never put real keys in `destination.json` shown to the user; use `<ACCESS_KEY>` placeholders.
- Do not drop or rewrite destination tables yourself; use `clear-destination` after the user agrees.
