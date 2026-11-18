# OLake CLI reference

Commands and flags come from
[`protocol/`](https://github.com/datazip-inc/olake-go/tree/master/protocol) in `datazip-inc/olake-go`.
Every flag: [flags.md](flags.md).

## Image

Every command runs from the released source image `olakego/source-<source>:<tag>`, where `<source>` is
one of `postgres mysql mongodb mssql oracle db2 s3 kafka`. The same image writes to every destination.

- Tags: [OLake releases](https://github.com/datazip-inc/olake-go/releases) or the
  [`olakego` images on Docker Hub](https://hub.docker.com/u/olakego).
- Get the latest release tag; do not hardcode one:

  ```bash
  gh release view -R datazip-inc/olake-go --json tagName -q .tagName
  # without gh:
  curl -s https://api.github.com/repos/datazip-inc/olake-go/releases/latest | jq -r .tag_name
  ```

- Pin that tag for the whole run. With `latest`, add `--pull=always` so Docker fetches the newest image.
- Do not build from source for a run. Use the released image.

## Mounts, network and output

- Mount one host folder at `/mnt/config` and keep every config in it:
  `-v "<CONFIG_DIR>:/mnt/config"`. Use an absolute host path.
- Network: inside the container `localhost` is the container itself.
  - Service on the host machine: use `host.docker.internal` in the config (on Linux also add
    `--add-host=host.docker.internal:host-gateway`).
  - Service in a Docker network (for example a catalog and MinIO from docker compose): add
    `--network <NETWORK>` and use the service names in the config.
- OLake writes its output next to `--config` (or next to `--destination` when there is no `--config`):
  `available_streams.json`, `selected_streams.json`, `state.json`, `stats.json` and
  `logs/sync_<UTC timestamp>/olake.log`.
- `--no-save` skips writing these files.

## Commands

The examples use a shell function so each command stays short. Add `--network <NETWORK>` inside it
when needed.

```bash
olake() {
  docker run --rm -v "<CONFIG_DIR>:/mnt/config" olakego/source-<source>:<tag> "$@"
}

# Config schema: source fields, or destination fields with --destination-type (iceberg or parquet)
olake spec
olake spec --destination-type iceberg

# Query engines OLake knows and the delete formats each can read
olake spec --available-query-engines

# Connection checks (one at a time)
olake check --config /mnt/config/source.json
olake check --destination /mnt/config/destination.json

# Discover streams -> available_streams.json + selected_streams.json
olake discover --config /mnt/config/source.json --destination /mnt/config/destination.json

# Sync (first run)
olake sync --config /mnt/config/source.json --destination /mnt/config/destination.json \
  --available-streams /mnt/config/available_streams.json \
  --selected-streams /mnt/config/selected_streams.json

# Sync (rerun from saved state)
olake sync --config /mnt/config/source.json --destination /mnt/config/destination.json \
  --available-streams /mnt/config/available_streams.json \
  --selected-streams /mnt/config/selected_streams.json \
  --state /mnt/config/state.json

# Delete destination data and state for the selected streams (destructive: confirm first)
olake clear-destination --destination /mnt/config/destination.json \
  --available-streams /mnt/config/available_streams.json \
  --selected-streams /mnt/config/selected_streams.json \
  --state /mnt/config/state.json
```

When the driver or destination skill has no field list, run `spec` (or `spec --destination-type`)
for the schema, then read the connector page on [olake.io/docs](https://olake.io/docs).

## Reading results

- `check` prints a `connectionStatus` message: `"status":"SUCCEEDED"` or `"status":"FAILED"` with a
  `message`. A source check also lists `prerequisites`, each with `name`, `required`, `passed`,
  `current_value` and `recommended_value`. Fix every entry with `"required":true,"passed":false`.
- `discover` logs the catalog and writes the two streams files.
- `sync` updates `stats.json` while it runs and writes `state.json` for `incremental` and `cdc` streams.
- Full log of a run: `<CONFIG_DIR>/logs/sync_<UTC timestamp>/olake.log`.

## Older `streams.json`

Releases before the split used one `streams.json` and `--streams`. It still works but logs a deprecation
warning. Convert it without connecting to the source:

```bash
olake discover --streams /mnt/config/streams.json --convert-streams
```
