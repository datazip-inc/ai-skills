# `state.json`

## What it is

The sync position per stream: CDC log position, incremental cursor value, and backfill progress.
`sync` writes it into the config folder. `full_refresh` streams keep no state.

## Rules

- First run: no `--state`.
- Every later run of `incremental`, `cdc` or `strict_cdc` streams: pass `--state /mnt/config/state.json`.
  Without it, OLake starts from scratch and re-copies the table.
- Keep the same `source.json`, `destination.json` and streams files between runs.
- Do not hand-edit or delete `state.json`. To restart one stream, run `clear-destination` for it
  (see `cli.md`); it removes that stream's destination data and its state entry.
- `state.json` carries a `version`. Keep the same image tag across reruns; do not downgrade the image
  after a newer one has written the state.

## Adding a stream to a running job

Rerun `discover` with the same `--destination`, add the stream to `selected_streams.json`, and sync with
`--state`. The new stream starts with its initial copy; the others continue from their saved position.
