# Collecting logs

Find the run mode first, then save the log of the failing step to a file and run
`scripts/triage_logs.py` on it. Do not paste whole logs into the conversation.

## CLI

- `olake-protocol/scripts/run_sync.sh` writes one log per stage in the config folder:
  `check-source.log`, `check-destination.log`, `discover.log`, `sync.log`.
- OLake also writes `<CONFIG_DIR>/logs/sync_<UTC timestamp>/olake.log` for each run.
- A command run by hand: add `> <CONFIG_DIR>/<stage>.log 2>&1`.

## Docker compose (OLake UI)

- Job run: `./olake-data/<RUN_FOLDER>/logs/sync_<timestamp>/olake.log` in the compose folder, or the
  run's logs in the UI.
- Services: `docker compose logs --tail=200 temporal-worker > worker.log 2>&1`, and the same for
  `olake-ui`.
- Details: `olake-deploy-docker-compose`, `references/logs.md`.

## Helm (Kubernetes)

- Worker: `kubectl logs -n olake deploy/olake-workers --tail=200 > worker.log`. It logs each job pod
  it starts and the pod's final status.
- Job pods are deleted when the run ends: `kubectl logs -n olake <POD>` works only while it runs.
  After that, read `<run folder>/logs/sync_<timestamp>/olake.log` from the job storage.
- Details: `olake-deploy-helm`, `references/logs.md`.

## From the user

- Ask for the failing step and the log file, or the last about 50 lines around the first error.
- Ask the user to remove passwords and keys before pasting: logs and `source.json` can hold them.
