---
name: olake-driver-abstract
description: "Source behaviour shared by every OLake driver: full_refresh, incremental, cdc and strict_cdc, chunked backfill and resume, cursor fields, CDC prerequisite checks. Use when picking a sync mode or cursor, when a backfill or CDC run stops or restarts, or when check reports failed prerequisites."
metadata:
  parent: olake-protocol
  status: experimental
---

# OLake sources: sync modes, backfill, CDC

What every driver (`postgres mysql mongodb mssql oracle db2 s3 kafka`) does the same way. The run itself
(`check`, `discover`, `sync`) is in `olake-protocol`; this skill explains how the source side behaves.

## When to use

- Pick or change `sync_mode`, `cursor_field` or `chunk_column` for a stream.
- A sync stopped during backfill or CDC and the user asks what a rerun does.
- `check` returned a `prerequisites` list with failed entries.
- The source has no driver skill yet: use the setup links below.
- Not covered: delete formats, partitioning, normalization: load `olake-destination-abstract`.

## Inputs to collect

| Input | Example | Where it comes from |
| --- | --- | --- |
| Source type | `mysql` | `source.json` / user |
| Streams and their `supported_sync_modes` | `["full_refresh","incremental","cdc"]` | `available_streams.json` |
| Wanted freshness | one-off copy, hourly, near real time | User |
| Can the source enable CDC? | binlog / WAL / oplog access | User or DBA |

## Prerequisites

- [ ] `discover` has run, so `available_streams.json` exists.
- [ ] For `cdc` or `strict_cdc`: the source's CDC settings are done. Per-driver setup:
      [references/driver-setup.md](references/driver-setup.md).

## Steps

1. Pick the mode per stream with [references/sync-modes.md](references/sync-modes.md#choosing-a-mode).
   Discover already set a default: `cdc` when the source supports it and CDC is configured, else
   `incremental`, else `strict_cdc`, else `full_refresh`.
2. For `incremental`, set `cursor_field` to a column that only grows (`updated_at`, an auto-increment id).
   It must be in `available_cursor_fields`. Discover defaults to the alphabetically first one, which is
   rarely the right column: check it. Use `primary:secondary` when the first can be null.
3. For `cdc`, run `check` and read the `prerequisites` list
   ([references/prerequisites.md](references/prerequisites.md)). Fix every `"required": true` entry
   with `"passed": false` before syncing.
4. Large table, slow backfill: set `chunk_column` to an indexed, evenly spread column, or raise
   `max_threads` in `source.json`. Details: [references/sync-modes.md](references/sync-modes.md#backfill).
5. Sync with `olake-protocol` step 6. Rerun with `--state` for every non-`full_refresh` stream.

## Verify

- Log shows `Starting backfill for stream[<name>] with <n> chunks`, then one
  `finished chunk min[...] and max[...]` line per chunk.
- On a rerun, `incremental` and `cdc` streams log `Backfill skipped for stream[...], already completed`
  or `backfill completed for stream[...], skipping`.
- `state.json` holds a cursor (incremental) or a log position (cdc) for each stream.

## Common errors

| Error (verbatim) | Cause | Fix |
| --- | --- | --- |
| `<driver> cdc configuration not provided, use full refresh for all streams` | A stream is `cdc`, but `source.json` has no CDC settings | Add the driver's CDC config, or switch the stream to `incremental` / `full_refresh`. |
| `required CDC prerequisites not met: <names>` | Source settings for CDC are missing | Fix each named setting ([references/driver-setup.md](references/driver-setup.md)), then `check` again. |
| `required CDC prerequisites could not be evaluated: <names>` | The check query failed: grants, network or timeout | Grant the user read access to the server settings, or fix connectivity. |
| `cursor value is nil in the metadata state ... cursor field got changed. Please run clear destination first` | `cursor_field` changed between runs | Confirm with the user, then `clear-destination` for that stream and sync again. |
| `max primary cursor value is nil for stream: <name>` (warning) | Cursor column is empty or all null | Pick another cursor, or use a `primary:secondary` cursor. |

Full list and resume rules: [references/sync-modes.md](references/sync-modes.md#reruns-and-resume)

## Next

- Delete formats, partitioning, normalization, `append_mode`: `olake-destination-abstract`.
- Files, flags and `--state`: `olake-protocol`.

## Rules

- Never switch a running stream's `sync_mode` or `cursor_field` without telling the user: it needs
  `clear-destination` and a full re-copy.
- Confirm with the user before changing source settings (WAL, binlog, replication slots); some need a
  database restart.
- Use `<PASSWORD>` placeholders; never print secrets.
