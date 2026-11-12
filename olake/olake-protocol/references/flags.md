# CLI flags

Flags apply to every command unless noted. Source: `protocol/root.go` in the olake repo.

| Flag | Default | Use |
| --- | --- | --- |
| `--config <file>` | | Source config. Required for `discover` and `sync`. |
| `--destination <file>` | | Destination config. Required for `sync` and `clear-destination`. |
| `--available-streams <file>` | | Streams from discover. Pass with `--selected-streams`. |
| `--selected-streams <file>` | | Streams to sync. Pass with `--available-streams`. |
| `--state <file>` | | Saved sync position. Pass on every rerun of `incremental` and `cdc` streams. |
| `--streams <file>` | | Deprecated single streams file. Do not combine with the pair above. |
| `--destination-type <type>` | | `spec` only: print a destination's config schema. |
| `--destination-buffer-size <n>` | `10000` | Writer batch size. |
| `--max-discover-threads <n>` | `50` | Parallel table discovery. |
| `--discover-schema` | `false` | `sync` only: re-discover and validate sync mode, primary keys and cursors before syncing. |
| `--destination-database-prefix <p>` | source type | Prefix for destination database names. |
| `--target-query-engines <list>` | | Comma-separated engines that read the tables (e.g. `spark,duckdb`). Narrows delete formats. Pass on every `discover`. |
| `--available-query-engines` | `false` | `spec` only: list engines and the delete formats they read. |
| `--timeout <sec>` | `-1` | Override default timeouts (discover default 5 minutes). |
| `--encryption-key <key>` | | Decrypt encrypted configs: KMS key ARN, UUID or custom string. |
| `--no-save` | `false` | Do not write streams, state, stats or log files. |
| `--convert-streams` | `false` | `discover` only: convert `--streams` into the two-file format. |
| `--difference-available-streams`, `--difference-selected-streams` | | `discover` only: compare with the current pair and write `difference_*.json`. |
