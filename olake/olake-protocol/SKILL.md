---
name: olake-protocol
description: "Start here for anything OLake. Set up and run a sync from any source to Iceberg or Parquet: check, discover, pick streams, sync, verify, rerun with state, clear. Use for a POC, 'replicate my <database> to Iceberg', running the OLake CLI, streams files, state.json or sync flags."
metadata:
  status: experimental
---

# Run OLake: check, discover, sync, verify

Base skill for every OLake run. It collects what the user wants, runs the basic path and loads the
source, destination and deploy skills for the details.

## When to use

- The user wants to set up or try OLake, or replicate a database or stream into Iceberg or Parquet.
- The user wants to run `check`, `discover`, `sync` or `clear-destination`, or rerun a sync.
- The user asks about `available_streams.json`, `selected_streams.json`, `state.json` or sync flags.

## Inputs to collect

Ask only for what is missing. Check the combination against
[references/compatibility-matrix.md](references/compatibility-matrix.md) before going further.

| Input | Example | Where it comes from |
| --- | --- | --- |
| Run mode | `cli`, `ui` | User. `cli`: the steps below. `ui`: deploy with `olake-deploy-docker-compose` (one machine) or `olake-deploy-helm` (Kubernetes), then [references/ui.md](references/ui.md). |
| Source type | `postgres` | One of `postgres mysql mongodb mssql oracle db2 s3 kafka`. |
| Source connection | host, port, database, user, `<PASSWORD>` | User. Field list in the driver skill. |
| Destination type | `iceberg` or `parquet` | User. |
| Catalog and storage (Iceberg) | REST catalog on MinIO | User. Field list in the destination skill. |
| Streams | `public.orders` | User, after discover. |
| Sync mode per stream | `cdc` | User. Default `full_refresh` if the user has no preference. |
| OLake version | latest release | Image tag. Look up the latest release (see [references/cli.md](references/cli.md#image)) and pin it, not `latest`, for anything beyond a first try. |
| Config folder (CLI) | `/abs/path/olake-run/` | User. Holds configs and every file OLake writes. |

## Prerequisites

- [ ] Docker is installed and running: `docker info` succeeds.
- [ ] The source and destination are reachable from where the containers run. From a container,
      `localhost` is the container itself; use the host name or `host.docker.internal`.
- [ ] Source prerequisites done (CDC settings, grants): follow the driver skill.
- [ ] Run through [references/poc-checklist.md](references/poc-checklist.md) for a POC.

## Steps

CLI mode uses one image per source: `olakego/source-<source>:<tag>`. The same image writes to every
destination. Full commands and mount rules: [references/cli.md](references/cli.md).

1. Create the config folder and write `source.json` and `destination.json` in it. Get the fields from
   the driver and destination skills. Use `<PASSWORD>` placeholders and ask the user to fill them in.

Steps 2 to 7 use [scripts/run_sync.sh](scripts/run_sync.sh). It runs the stage, keeps the full log in
the config folder (`<stage>.log`), prints a short summary, and on failure prints the matching error
rows from every skill. Add `--tag <tag>` and, for services in a Docker network, `--network <name>`.
The raw `docker run` commands: [references/cli.md](references/cli.md).

2. Check the source: `scripts/run_sync.sh <source> <CONFIG_DIR> --stages check-source`
3. Check the destination: `scripts/run_sync.sh <source> <CONFIG_DIR> --stages check-destination`
   On `FAILED`, act on the matched error rows; with none, read the `message` and `prerequisites`
   in the stage log with `grep connectionStatus`, then load the matching skill.
4. Discover streams: `scripts/run_sync.sh <source> <CONFIG_DIR> --stages discover`. It writes
   `available_streams.json` and `selected_streams.json` and lists the selected streams.
   Steps 2 to 4 in one call: `--stages check,discover`.
5. Edit `selected_streams.json`: keep only the streams the user wants and set `sync_mode`,
   `cursor_field`, `normalization`, `partition_regex` per stream. Field reference:
   [references/streams.md](references/streams.md). Do not edit `available_streams.json`.
6. Sync: `scripts/run_sync.sh <source> <CONFIG_DIR> --stages sync`. It prints the records read.
7. Rerun for `incremental` and `cdc` streams: `scripts/run_sync.sh <source> <CONFIG_DIR> --stages sync --state`.
   Without `--state` the sync starts over. Details: [references/state.md](references/state.md).

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

- Schedule the sync: run the step 7 command from cron or any scheduler, always with `--state`.
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
