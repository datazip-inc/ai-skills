# `partition_regex`

Set per stream in `selected_streams.json`. Empty means no partitioning. Use `now()` as the column to
partition by sync time (`_olake_timestamp`). The two writers use different syntax.

## Iceberg: `/{column, transform}`

Iceberg hidden partitioning. One `{column, transform}` block per partition field, in order.

```text
/{created_at, day}
/{customer_id, bucket[16]}/{created_at, month}
/{now(), hour}
```

| Transform | Column types | Result |
| --- | --- | --- |
| `identity` | any | One partition per value. Only for low-cardinality columns. |
| `year`, `month`, `day`, `hour` | date, timestamp | Time buckets. |
| `bucket[N]` | any | Hash into `N` buckets. Spreads high-cardinality keys. |
| `truncate[W]` | string, number | Prefix of width `W`, or value rounded down to a multiple of `W`. |
| `void` | any | Always null; keeps a dropped partition field. |

A pattern without a valid block fails with `no matches found for partition regex: <pattern>`.

## Parquet: `/{column, default, granularity}`

Folder layout. Each block becomes one folder level; text outside blocks is kept as-is.

```text
/{created_at, unknown, YYYY}/{created_at, unknown, MM}
/{region, no_region, }
/{now(), , DD}
```

| Part | Meaning |
| --- | --- |
| `column` | Column name, or `now()`. |
| `default` | Folder name when the value is null. Empty means `default_<column>`. |
| `granularity` | Empty for the raw value; `YYYY`, `MM`, `WW` (ISO week), `DD`, `HH` for time parts in UTC. |

## Choosing partitions

- Partition by the column most queries filter on, usually a date: `day` or `month`.
- Aim for partitions of hundreds of MB, not thousands of tiny files. Prefer `month` for small tables.
- Do not use `identity` on ids or timestamps.
- Changing `partition_regex` after the first sync needs `clear-destination` and a full re-sync.

Docs: [Iceberg partitioning](https://olake.io/docs/writers/iceberg/partitioning),
[Parquet partitioning](https://olake.io/docs/writers/parquet/partitioning).
