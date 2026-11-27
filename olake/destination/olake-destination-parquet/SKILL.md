---
name: olake-destination-parquet
description: "Write OLake syncs as plain Parquet files (mirrors destination/parquet): destination.json for local disk, Amazon S3, MinIO, GCS (S3 interop with HMAC keys) and Azure Blob / ADLS, the folder layout OLake writes, partition_regex folders, file size, and checking the files. Use when the destination is Parquet files rather than Iceberg tables, or the user wants the simplest local test target."
metadata:
  parent: olake-destination-abstract
  status: experimental
---

# Parquet destination

`"type": "PARQUET"` in `destination.json`. Every source image writes it. Files only: no catalog, no
upserts, no deletes. Every change is a new row (`_op_type` tells inserts, updates and deletes apart).
How OLake shapes columns is in `olake-destination-abstract`; the run is in `olake-protocol`.

## When to use

- The destination is Parquet files on local disk, S3, MinIO, GCS or Azure.
- The user wants a quick target to try a source, without a catalog.
- Not covered: tables with upserts and deletes → `olake-destination-iceberg`.

## Inputs to collect

| Input | Example | Where it comes from |
| --- | --- | --- |
| Storage | local, S3, MinIO, GCS, Azure | User |
| Bucket / container and path | `my-bucket`, `/olake` | User |
| Region (S3) | `us-east-1` | User |
| Keys | `<ACCESS_KEY>`, `<SECRET_KEY>` | User. S3 on AWS: leave out to use the instance role. |
| Partition folders? | `/year={created_at,,YYYY}` | User, optional |

## Steps

1. Write `destination.json`. Local disk (files land in the config folder on the host):
   ```json
   { "type": "PARQUET", "writer": { "local_path": "/mnt/config/output" } }
   ```
   S3, MinIO, GCS and Azure: [references/storage.md](references/storage.md). Every field:
   [references/config.md](references/config.md).
2. `check --destination` (`olake-protocol` step 2). For object storage it writes a small test file
   under `<s3_path>/olake_writer_test/` and leaves it there; safe to delete.
3. Discover. Optional: set `partition_regex` per stream in `selected_streams.json`
   ([references/partitioning.md](references/partitioning.md)).
4. Sync, then rerun with `--state` (`olake-protocol`).

## Where the files land

```text
<local_path | s3://<s3_bucket><s3_path> | <container><azure_path>>/<namespace>/<table>/[<partition folders>/]<UTC timestamp>_<id>.parquet
```

- Namespace: `destination_database` from `discover`, for example `postgres_shop_public`.
- File name: `<YYYY-MM-DD_HH-MM-SS>_<id>.parquet` (UTC). Each table folder also gets a small
  `metadata.json` written by OLake.
- A new file per sync and per partition; a file rolls over at `max_file_size_mb` (default 512).
- Object storage: files are written to a temp folder in the container and uploaded when the writer
  closes, so they appear in the bucket at the end of each stream's run.

## Verify

- Files exist under `<namespace>/<table>/`: `find <CONFIG_DIR>/output -name '*.parquet'` (local),
  `aws s3 ls --recursive s3://<bucket><path>/` (S3).
- Row count across a table's files equals the source rows for the first sync:
  `duckdb -c "SELECT COUNT(*) FROM '<path>/<namespace>/<table>/**/*.parquet'"`.
- A rerun adds new files only; earlier files are never changed.

## Common errors

| Error | Cause | Fix |
| --- | --- | --- |
| `failed to create AWS session: invalid configuration` | Keys or region missing or wrong | Set `s3_region` and keys, or attach a role. MinIO and GCS need keys. |
| `AccessDenied` / `403 Forbidden` on the test file or upload | Missing S3 actions | Policy in [references/storage.md](references/storage.md#s3). |
| `storage_type must be "S3" or "Azure"` | Typo in `storage_type` | Use `S3` or `Azure`. |
| `azure_container_name is required` | Azure without container | Set `azure_container_name`. |

## Next

- Partition folders: [references/partitioning.md](references/partitioning.md).
- Columns, normalization and schema changes: `olake-destination-abstract`.

## Rules

- Too many partition folders make many tiny files: keep partition cardinality low (dates, not ids).
- Never print keys, SAS tokens or connection strings; use placeholders.
