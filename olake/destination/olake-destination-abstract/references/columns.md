# Columns OLake adds, normalization, schema changes

## OLake columns

Every row gets these columns:

| Column | Type | Meaning |
| --- | --- | --- |
| `_olake_id` | string | Hash of the primary key columns. The upsert key. |
| `_olake_timestamp` | timestamp | When OLake wrote the row (UTC). |
| `_op_type` | string | `r` backfill read, `c` insert, `i` insert during the backfill overlap, `u` update (and every incremental row), `d` delete. |
| `_cdc_timestamp` | timestamp | Source commit time of the change. `cdc` and `strict_cdc` only; backfill rows hold `1970-01-01`. Not added for Kafka. |

Some drivers add their own CDC metadata columns (for example a log position).

## Normalization

| `normalization` | Table shape |
| --- | --- |
| `true` (default for postgres, mysql, oracle, db2, mssql) | One column per top-level field. Nested JSON stays one column. |
| `false` (default for mongodb, s3, kafka) | The record is one JSON string column `data`, plus the OLake columns and any partition columns. |

Column names are lowercased and every character outside `a-z 0-9` becomes `_`, unless
`use_source_column_names: true` is set on the stream.
`filter_config` needs `normalization: true`.

## Schema changes

- New source column: added to the table on the next sync (with `selected_columns.sync_new_columns: true`
  when columns are limited).
- Wider type (int to long, float to double): the column is promoted.
- Incompatible type change: the sync fails with a schema error; the stream needs `clear-destination`
  and a re-sync.
- Dropped source column: stays in the table, filled with null from then on.

Details: [Schema evolution](https://olake.io/docs/features/schema).
