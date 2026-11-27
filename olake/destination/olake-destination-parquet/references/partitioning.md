# Parquet partition folders

Set `partition_regex` per stream in `selected_streams.json`. Each `/...` segment becomes a folder level
under `<namespace>/<table>/`. Docs: [Parquet partitioning](https://olake.io/docs/writers/parquet/partitioning).

```json
{ "stream_name": "orders", "sync_mode": "cdc", "partition_regex": "/year={created_at,,YYYY}/month={created_at,,MM}" }
```

Result: `postgres_shop_public/orders/year=2026/month=11/<file>.parquet`.

A segment is `{column, default, granularity}`:

| Part | Meaning |
| --- | --- |
| `column` | Column whose value names the folder, or `now()` for the sync time. |
| `default` | Optional. Used, prefixed with `default_`, when the value is null or cannot be parsed. |
| `granularity` | Optional, time columns only: `HH`, `DD`, `WW`, `MM`, `YYYY`. |

Text outside `{...}` is kept as is (`year=`), so Hive-style `key=value` folders work with Spark,
Trino, Athena and DuckDB (`hive_partitioning`).

- Keep cardinality low: one folder per value. Partitioning by an id makes a file per row.
- Changing `partition_regex` affects only new files; old files stay in their folders.
