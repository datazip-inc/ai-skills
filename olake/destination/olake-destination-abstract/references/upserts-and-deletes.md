# Upserts, deletes and query engines

## Append or upsert

| `append_mode` | Writes | Use when |
| --- | --- | --- |
| `false` (default for SQL sources and MongoDB) | Upsert by `_olake_id`: one live row per primary key; deletes remove the row. Iceberg only. | The table should mirror the source. |
| `true` (default for `s3`, `kafka`) | Every record is a new row, deletes included (`_op_type` `d`). | History or event logs, or Parquet. |

Parquet always appends: `append_mode` and `update_type` have no effect there.
A stream without a primary key upserts nothing useful: use `append_mode: true`.
Postgres with `preserve_toast_values` allows only upserts (`append_mode: false`).

## Delete formats (`update_type`, Iceberg upserts)

| Value | What Iceberg gets | Cost |
| --- | --- | --- |
| `eq` | Equality delete files keyed on `_olake_id`. | Cheapest to write; readers do more work. Default. |
| `pos` | Positional delete files (data file + row number). | OLake keeps a local row index; reads are faster. |
| `dv` | Iceberg v3 deletion vectors. | Same index as `pos`; table must be format version 3. |

`discover` lists the formats the stream can use in `available_update_types`. The list is narrowed by:

- the query engines passed with `--target-query-engines`;
- the catalog: `unity` allows only `dv`; `horizon` (Snowflake) only `pos` and `dv`; `nessie` only `eq` and `pos`;
- the source: `kafka` and Postgres with `preserve_toast_values` cannot use `eq`.

## Which engines read which formats

List the current matrix from the image: `olake spec --available-query-engines`.

| Engine | `eq` | `pos` | `dv` |
| --- | --- | --- | --- |
| Spark, Flink, Trino, DuckDB | yes | yes | yes |
| Presto, StarRocks, Hive, Athena, BigQuery | yes | yes | no |
| Snowflake | no | yes | yes |
| Databricks | no | no | yes |

If the engine cannot read the format, deleted or updated rows show up as duplicates.
Ask the user which engines will read the tables before the first `discover`.

## Changing it later

Changing `append_mode` or `update_type` on a synced stream needs the user's go-ahead: it may need
`clear-destination` and a re-sync. If a rerun of `discover` drops the old format, OLake moves `eq` to
the first available format, and clears any other value with a warning until the user picks one.
