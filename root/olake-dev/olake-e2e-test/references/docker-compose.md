# Environment: docker compose

The OLake stack (UI and API server, Temporal, worker) runs with `docker compose` from the olake-ui repo's `docker-compose-v1.yml`, plus an override file in the run directory.
The test source and destination run beside it, as described in the test data reference.

The worker starts one driver container per task (spec, check, discover, sync) on the default bridge network.
It looks for `olakego/source-<driver>:<version>` locally first and pulls only when the image is missing.
`<version>` is the `version` field of the source in OLake.

## Contents

- Ports
- 1. Override file and start
- 2. Deploy gate
- 3. Logs: workflow directories, `worker.log`, `olake.log`
- 4. Handoff rows
- 5. Teardown

## Ports

| Port | Service |
| --- | --- |
| 8000 | OLake UI and API |
| 8081 | Temporal UI, only with `--profile debug` on the compose command |

## 1. Override file and start

Write `<run-dir>/compose.override.yml` with an image for both services: the run tag when the stack built it, otherwise the pinned release tag recorded in `stack.md`.

```yaml
services:
  olake-ui:
    image: olakego/ui:<tag>
    pull_policy: missing
    environment:
      TELEMETRY_DISABLED: "true"
      APP_ENV: development
      CUSTOM_DRIVER_VERSION: <driver tag>
  temporal-worker:
    image: olakego/ui-worker:<tag>
    pull_policy: missing
    environment:
      TELEMETRY_DISABLED: "true"
```

- Never leave out an `image` line: the compose default is `latest`, always pulled, so the stack would run whatever was published last.
- Keep both `environment` blocks always, and drop only `APP_ENV` and `CUSTOM_DRIVER_VERSION` when no driver was built.
  Together they make the UI offer the local driver tag and skip its version checks.
- An override, not an edit to `docker-compose-v1.yml`: the compose file may be the user's working copy, or a read-only checkout of a repo that was not built.

The compose file comes from `<olake-ui>`; when olake-ui is not part of the change, that is the managed clone at the pinned release tag of `olakego/ui`, so the compose file matches the images.
Start it from the run directory, so the compose file's `${PWD}/olake-data` bind mount lands there and not in the repo:

```bash
cd <run-dir> && docker compose -p olake-dev-<run-id> -f <olake-ui>/docker-compose-v1.yml -f compose.override.yml up -d
```

To change an image on a running stack, update the override and run the same `up -d`: compose recreates only the changed services and keeps the volumes.

## 2. Deploy gate

```bash
${CLAUDE_SKILL_DIR}/scripts/compose-gate.sh olake-dev-<run-id> <run-dir>
```

It waits until every service with a healthcheck is healthy, every one-shot service (the migrations, `signup-init`) exited 0 and every other service runs, then logs in and writes `<run-dir>/cookies.txt`.
It ends with `GATE PASS`, or `GATE FAIL: <reason>` and the state of every service.
Then check its `image` lines: the run tag for each built image, the pinned release tag for the others.

## 3. Logs

Every task writes its files to a workflow directory, `<run-dir>/olake-data/<workflow-dir>/`.
The worker names it from the Temporal workflow ID:

| Task | `<workflow-dir>` | Example |
| --- | --- | --- |
| Spec, test connection, discover, stream difference | The workflow ID, which is the `operation_id` that `api-op.py` prints | `discover-catalog-123-8f14e45fceea167a5a36dedd4bea2543` |
| Sync, clear destination | SHA-256 of the workflow ID `sync-<project>-<job id>-<start time>` | `printf %s 'sync-123-3-2026-11-12T12:34:03Z' \| shasum -a 256` |

The worker log line `running container` gives it as `containerName`, with the command and the image tag.
Every directory has `logs/worker.log`: the worker's JSON log for that one task, the first file to read when a task fails.
It shows the job name, ID and attempt, the image tag and whether it came from the local cache or a pull, the driver command line, a one-line failure summary, and the persisted state.
A sync directory also has `source.json`, `destination.json`, the streams files, `state.json`, `stats.json` (Synced Records, once written) and `logs/sync_<time>/olake.log`.
The worker removes the driver container when the task ends, so read these files, not `docker logs`.

| What | Command |
| --- | --- |
| Which workflow directory a task used | `docker logs olake-temporal-worker 2>&1 \| grep 'running container' \| cut -c1-250`: `containerName` is `<workflow-dir>` |
| Rows a sync wrote (`Synced Records`; a progress file, not the status, which comes from the job tasks API) | `cat <run-dir>/olake-data/<workflow-dir>/stats.json` |
| Sync log | `grep -h -i -E 'error\|fatal\|creating table\|successfully wrote' <run-dir>/olake-data/<workflow-dir>/logs/*/olake.log \| cut -c1-250` |
| One task, from the worker | `grep -h -E '"level":"(error\|warn)"\|running container\|Using image' <run-dir>/olake-data/<workflow-dir>/logs/worker.log \| cut -c1-250` |
| Worker, across tasks (start-up, Temporal connection) | `docker logs --since 10m olake-temporal-worker 2>&1 \| grep -i -E 'error\|fail' \| cut -c1-250` |
| UI and API | `docker logs --since 10m olake-ui 2>&1 \| grep -i -E 'error\|fail' \| cut -c1-250` |

## 4. Handoff rows

| What | Value |
| --- | --- |
| OLake UI | `http://localhost:8000`, login `admin` / `password` |
| API | `http://localhost:8000/api/v1/project/123`, cookie login with `POST /login` |
| Temporal UI | `http://localhost:8081`, when the stack was started with `--profile debug` |
| Driver version to pick in the UI | The run tag, when a driver was built; else the pinned release tag |
| Image tags in use | One line per image |
| Logs | Section 3 |

## 5. Teardown

```bash
cd <run-dir> && docker compose -p olake-dev-<run-id> -f <olake-ui>/docker-compose-v1.yml -f compose.override.yml down -v
```

Remove the stack's images only when the user asks: `docker rmi <image>:<tag>`.
