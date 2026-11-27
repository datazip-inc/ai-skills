# Logs (docker compose)

Run every command from the folder that holds the compose file (or add `-f <file>`).

## Stack services

| Service | Container | Look here for |
| --- | --- | --- |
| `olake-ui` | `olake-ui` | API errors, login, saving sources and destinations. |
| `temporal-worker` | `olake-temporal-worker` | Job start, image pulls, driver container launch, log cleaner. |
| `temporal` | `temporal` | Workflow engine; database connection at start. |
| `postgresql` | `temporal-postgresql` | Database start and health. |
| `signup-init` | `olake-signup-init` | Admin user creation. |

```bash
docker compose ps
docker compose logs -f --tail=200 temporal-worker
docker compose logs olake-ui | grep -i error
```

`temporal-worker` logs `running container` with the command, image and container name for each run.
The log cleaner writes `Log cleaner started...`, then `Running log cleaner...` daily, and
`Deleting folder <path>` for each removed folder.

## A job run

The driver writes its log to the run folder (see [volumes.md](volumes.md#run-folders-in-olake-data)):

```bash
ls -t ./olake-data/<RUN_FOLDER>/logs/
tail -f ./olake-data/<RUN_FOLDER>/logs/sync_<timestamp>/olake.log
```

The UI shows the same log on the job's run page. The driver container is named after the run folder
while it runs: `docker logs -f <RUN_FOLDER>`.

Find the first `ERROR` or `FATAL` line, then match it in the driver or destination skill
(`olake-driver-*`, `olake-destination-*`). Never paste a whole log into a ticket without checking it for
credentials.

## Temporal UI

```bash
docker compose --profile debug up -d temporal-ui
```

Open `http://localhost:8081`. It shows each workflow (`sync-<projectID>-<jobID>`, test and discover
runs), its retries and the activity error. Use it when a job is stuck in running or queued and
`olake.log` has nothing new.
