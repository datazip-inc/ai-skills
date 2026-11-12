# OLake CLI reference

Every command runs from the source driver image: `olakego/source-<source>:<tag>`, where `<source>` is one of
`postgres mysql mongodb mssql oracle db2 s3 kafka`. The same image writes to every destination.

## Mounts and paths

- Mount one host folder at `/mnt/config` and keep every config in it:
  `-v "<CONFIG_DIR>:/mnt/config"`. Use an absolute host path.
- OLake writes its output next to `--config` (or next to `--destination` when there is no `--config`):
  `available_streams.json`, `selected_streams.json`, `state.json`, `stats.json` and `logs/sync_<UTC timestamp>/olake.log`.
- `--no-save` skips writing these files.
- Add `--pull=always` when using `latest` so Docker fetches the newest image.

## Commands

```bash
IMG=olakego/source-<source>:<tag>
RUN="docker run --rm -v <CONFIG_DIR>:/mnt/config $IMG"

# Config schema the UI renders (source, or a destination with --destination-type)
$RUN spec
$RUN spec --destination-type iceberg

# Query engines OLake knows and the delete formats each can read
$RUN spec --available-query-engines

# Connection checks (one at a time)
$RUN check --config /mnt/config/source.json
$RUN check --destination /mnt/config/destination.json

# Discover streams -> available_streams.json + selected_streams.json
$RUN discover --config /mnt/config/source.json --destination /mnt/config/destination.json

# Sync (first run)
$RUN sync --config /mnt/config/source.json --destination /mnt/config/destination.json \
  --available-streams /mnt/config/available_streams.json \
  --selected-streams /mnt/config/selected_streams.json

# Sync (rerun from saved state)
$RUN sync ... --state /mnt/config/state.json

# Delete destination data and state for the selected streams (destructive: confirm first)
$RUN clear-destination --destination /mnt/config/destination.json \
  --available-streams /mnt/config/available_streams.json \
  --selected-streams /mnt/config/selected_streams.json \
  --state /mnt/config/state.json
```

## Reading results

- `check` prints a `connectionStatus` message: `"status":"SUCCEEDED"` or `"status":"FAILED"` with a
  `message`. A source check also lists `prerequisites`, each with `name`, `required`, `passed`,
  `current_value` and `recommended_value`. Fix every entry with `"required":true,"passed":false`.
- `discover` logs the catalog and writes the two streams files.
- `sync` updates `stats.json` while it runs and writes `state.json` for `incremental` and `cdc` streams.

## Older `streams.json`

Releases before the split used one `streams.json` and `--streams`. It still works but logs a deprecation
warning. Convert it without connecting to the source:

```bash
$RUN discover --streams /mnt/config/streams.json --convert-streams
```
