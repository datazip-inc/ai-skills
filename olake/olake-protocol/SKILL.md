---
name: olake-protocol
description: "Run OLake end to end for any source and destination: check the connections, discover streams, pick streams and sync modes, sync, verify, rerun with state, and clear. Use when the user wants to set up, try, or run OLake (a POC, 'replicate my Postgres/MySQL/MongoDB/... to Iceberg or Parquet'), run a sync with the OLake CLI or UI, or asks about streams files, state.json, sync flags or rerunning a sync. Entry point for every other OLake skill."
metadata:
  olake_version: v1.1.2
  status: experimental
---

# Run OLake: check, discover, sync, verify

Base skill for every OLake run. It collects what the user wants, runs the basic path and loads the
source, destination and deploy skills for the details.

## When to use

- The user wants to set up or try OLake, or replicate a database or stream into Iceberg or Parquet.
- The user wants to run `check`, `discover`, `sync` or `clear-destination`, or rerun a sync.
- The user asks about `available_streams.json`, `selected_streams.json`, `state.json` or sync flags.
- Not covered here:
  - Source prerequisites and config fields → `olake-driver-<source>` (for example `olake-driver-postgres`).
  - Sync mode behaviour (backfill, CDC, incremental, cursors) → `olake-driver-abstract`.
  - Catalog, storage and writer config → `olake-destination-<type>` (for example `olake-destination-iceberg`).
  - Normalization, partitioning, writer errors → `olake-destination-abstract`.
  - Bringing up the OLake UI → `olake-deploy-docker-compose`.
  - A failed step → `olake-troubleshoot`.

## Inputs to collect

Ask only for what is missing. Check the combination against
[references/compatibility-matrix.md](references/compatibility-matrix.md) before going further.

| Input | Example | Where it comes from |
| --- | --- | --- |
| Run mode | `cli` or `ui` | User. Default to `ui` for a POC that will be scheduled, `cli` for a one-off run. |
| Source type | `postgres` | One of `postgres mysql mongodb mssql oracle db2 s3 kafka`. |
| Source connection | host, port, database, user, `<PASSWORD>` | User. Field list in the driver skill. |
| Destination type | `iceberg` or `parquet` | User. |
| Catalog and storage (Iceberg) | REST catalog on MinIO | User. Field list in the destination skill. |
| Streams | `public.orders` | User, after discover. |
| Sync mode per stream | `cdc` | User. Default `full_refresh` if the user has no preference. |
| OLake version | `v1.1.2` | Image tag. Use a pinned tag, not `latest`, for anything beyond a first try. |
| Config folder (CLI) | `/abs/path/olake-run/` | User. Holds configs and every file OLake writes. |

## Prerequisites

- [ ] Docker is installed and running: `docker info` succeeds.
- [ ] The source and destination are reachable from where the containers run. From a container,
      `localhost` is the container itself; use the host name or `host.docker.internal`.
- [ ] Source prerequisites done (CDC settings, grants): follow the driver skill.
- [ ] For `ui` mode, OLake UI is up: follow `olake-deploy-docker-compose`.
- [ ] Run through [references/poc-checklist.md](references/poc-checklist.md) for a POC.

## Steps

CLI mode uses one image per source: `olakego/source-<source>:<tag>`. The same image writes to every
destination. Full commands and mount rules: [references/cli.md](references/cli.md).
UI mode: [references/ui.md](references/ui.md).

1. Create the config folder and write `source.json` and `destination.json` in it. Get the fields from
   the driver and destination skills. Use `<PASSWORD>` placeholders and ask the user to fill them in.
2. Check the source connection:
   ```bash
   docker run --rm -v "<CONFIG_DIR>:/mnt/config" olakego/source-<source>:<tag> \
     check --config /mnt/config/source.json
   ```
3. Check the destination connection:
   ```bash
   docker run --rm -v "<CONFIG_DIR>:/mnt/config" olakego/source-<source>:<tag> \
     check --destination /mnt/config/destination.json
   ```
   Success is a `connectionStatus` message with `"status":"SUCCEEDED"`. On `FAILED`, read
   `message` and the `prerequisites` list, then load the matching skill.
4. Discover streams. Pass the destination so the defaults fit it:
   ```bash
   docker run --rm -v "<CONFIG_DIR>:/mnt/config" olakego/source-<source>:<tag> \
     discover --config /mnt/config/source.json --destination /mnt/config/destination.json
   ```
   This writes `available_streams.json` and `selected_streams.json` into the config folder.
5. Edit `selected_streams.json`: keep only the streams the user wants and set `sync_mode`,
   `cursor_field`, `normalization`, `partition_regex` per stream. Field reference:
   [references/streams.md](references/streams.md). Do not edit `available_streams.json`.
6. Sync:
   ```bash
   docker run --rm -v "<CONFIG_DIR>:/mnt/config" olakego/source-<source>:<tag> \
     sync --config /mnt/config/source.json --destination /mnt/config/destination.json \
     --available-streams /mnt/config/available_streams.json \
     --selected-streams /mnt/config/selected_streams.json
   ```
7. Rerun for `incremental` and `cdc` streams: add `--state /mnt/config/state.json` to the step 6
   command. Without `--state` the sync starts over. Details: [references/state.md](references/state.md).

## Verify

- The sync log ends without a `fatal` or `error` line, and `stats.json` in the config folder shows
  `Synced Records` greater than 0.
- `state.json` exists in the config folder after a sync with `incremental` or `cdc` streams.
- The destination table exists and its row count matches the source:
  run `SELECT COUNT(*)` on the source table and the verify query from the destination skill.
- For `cdc`: insert one row in the source, rerun with `--state`, and confirm the count rises by one.

## Common errors

| Error (verbatim) | Cause | Fix |
| --- | --- | --- |
| `--config not passed` | `discover` or `sync` run without `--config` | Add `--config /mnt/config/source.json`. |
| `no valid streams found in catalog` | Every selected stream was skipped; the reason is in an earlier `Skipping; Configured Stream ...` log line | Fix what that line names (stream gone from source, bad sync mode or cursor, bad filter), or rerun `discover`. |
| `--available-streams and --selected-streams must be passed` | Only one of the pair was passed | Pass both files. |
| `--streams cannot be combined with --available-streams/--selected-streams` | Old and new stream files mixed | Use only the new pair. Convert an old `streams.json` with `discover --streams <file> --convert-streams`. |
| `no streams found in connector` | The user in `source.json` sees no tables, or the database is empty | Check the database name and the user's grants (driver skill). |

Everything else: load `olake-troubleshoot`.

## Next

- Schedule the sync, or hand it to a team: switch to `ui` mode with `olake-deploy-docker-compose`.
- Tune sync modes, cursors or CDC: `olake-driver-abstract` and the driver skill.
- Partitioning, normalization or delete formats: `olake-destination-abstract` and the destination skill.
- Every CLI flag: [references/flags.md](references/flags.md).
- Background: [references/architecture.md](references/architecture.md).

## Rules

- Use `<PASSWORD>`-style placeholders in every config. Never print, log or echo secrets back.
- Confirm with the user before `clear-destination`: it deletes destination data and state for the
  selected streams.
- Tell the user before a `full_refresh` rerun: it drops and rewrites the destination table.
- Do not delete or hand-edit `state.json`. To restart a stream, use `clear-destination`.
- Use released images (`olakego/source-<source>:<tag>`), not source builds.
