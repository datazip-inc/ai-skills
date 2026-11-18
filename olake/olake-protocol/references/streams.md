# Streams files

`discover` writes two files into the config folder.

## `available_streams.json`

What the source has, one entry per table or collection under `streams[]`. **Do not edit it.**
Read it to see what each stream supports:

| Field | Meaning |
| --- | --- |
| `stream.name`, `stream.namespace` | Table and schema/database |
| `stream.supported_sync_modes` | Modes allowed for this stream |
| `stream.source_defined_primary_key` | Primary key columns |
| `stream.available_cursor_fields` | Columns usable as `cursor_field` for `incremental` |
| `stream.available_update_types` | Delete formats the destination and query engines allow (`eq`, `pos`, `dv`) |
| `stream.type_schema` | Columns and types |

## `selected_streams.json`

What to sync, grouped by namespace. `discover` lists every stream; remove the ones the user does not want.

```json
{
  "selected_streams": {
    "public": [
      {
        "stream_name": "orders",
        "sync_mode": "cdc",
        "normalization": true,
        "partition_regex": "",
        "append_mode": false
      }
    ]
  }
}
```

| Field | Values | Notes |
| --- | --- | --- |
| `stream_name` | table name | Must exist in `available_streams.json`. |
| `sync_mode` | `full_refresh`, `incremental`, `cdc`, `strict_cdc` | Must be in `supported_sync_modes`. See below. |
| `cursor_field` | column, or `primary:secondary` | Required for `incremental`. From `available_cursor_fields`. |
| `normalization` | `true` / `false` | `true` turns top-level JSON fields into columns. Required for filters. |
| `partition_regex` | e.g. `/{created_at, year}` | Destination partitioning. See `olake-destination-abstract`. |
| `append_mode` | `true` / `false` | `true` disables upserts: rows are only appended. |
| `update_type` | `eq`, `pos`, `dv` | Delete format for upserts. Must be in `available_update_types`. |
| `selected_columns` | `{ "columns": [...], "sync_new_columns": true }` | Limit columns. `sync_new_columns` picks up new source columns. |
| `filter_config` | `{ "logical_operator": "AND", "conditions": [{ "column": "id", "operator": ">", "value": 100 }] }` | At most 2 conditions. Operators `>`, `<`, `=`, `!=`, `>=`, `<=`. |
| `chunk_column` | column | Column to split the backfill into chunks. |
| `destination_database`, `destination_table` | names | Override where the stream lands. |

## Sync modes

| Mode | What it does | Rerun |
| --- | --- | --- |
| `full_refresh` | Copies the whole table. | Drops and rewrites the destination table every run. |
| `incremental` | Full copy first, then only rows whose `cursor_field` moved past the saved value. | Needs `--state`. |
| `cdc` | Full copy first, then inserts, updates and deletes from the change log. | Needs `--state`. |
| `strict_cdc` | Change log only, no initial copy. | Needs `--state`. |

Source settings that `cdc` and `strict_cdc` need are in the driver skill. Mode internals: `olake-driver-abstract`.

## Why a stream is skipped

`sync` logs `Skipping; Configured Stream <namespace.table> ...` and continues with the other streams when:

- the stream is no longer in the source,
- its `sync_mode`, `cursor_field` or primary key does not match the source,
- its `update_type` is not valid for the destination,
- its filter has more than 2 conditions, an empty or unknown column, or a value of the wrong type.

If every stream is skipped, the sync fails with `no valid streams found in catalog`.
