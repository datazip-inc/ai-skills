# Environment: docker compose

Two stacks run side by side on the host Docker daemon.

| Stack | Defined in | Started by |
| --- | --- | --- |
| Test source and destination: Postgres, MinIO, Iceberg JDBC catalog, Spark | olake repo: `drivers/<driver>/docker-compose.yml`, `destination/iceberg/local-test/docker-compose.yml` | `make` targets in the olake repo |
| OLake: UI and API server, Temporal, worker | olake-ui repo: `docker-compose-v1.yml` | `docker compose` with an override file from the run directory |

The worker starts one driver container per task (spec, check, discover, sync) on the default bridge network.
It looks for `olakego/source-<driver>:<version>` locally first and pulls only when the image is missing.
`<version>` is the `version` field of the source in OLake.

## Contents

- Ports
- 1. Test source and destination: start, check Spark, seed
- 2. OLake stack: override file, start, deploy gate
- 3. API: login, call order, `api-op.py`
- 4. Connection values for the source and the Iceberg destination
- 5. Verify with Spark, and the source dump
- 6. Logs: workflow directories, `worker.log`, `olake.log`
- 7. Stack handoff table
- 8. Teardown

## Ports

| Port | Service |
| --- | --- |
| 8000 | OLake UI and API |
| 8081 | Temporal UI, only with `--profile debug` on the compose command |
| 5433 | Test Postgres (source) |
| 5432 | Iceberg JDBC catalog Postgres |
| 9000, 9001 | MinIO API, MinIO console |
| 15002 | Spark Connect |
| 8088 | Spark UI |

## 1. Test source and destination

```bash
make -C <olake> olake.postgres.start
make -C <olake> olake.destination.all.start
```

Both targets wait until the services answer.
They use the fixed compose projects `postgres` and `local-test`, and their teardown targets delete those projects' volumes and data folder. <!-- TODO[BEFORE_MERGE]: olake#4 -->
When the preflight record already lists either project, the user started it: ask before reusing it, and never run its teardown target.
Then check Spark with a real query:

```bash
docker exec spark-iceberg /opt/spark/bin/spark-sql -e "SHOW NAMESPACES IN olake_iceberg"
```

If it fails on the first boot (a jar download race), run `docker restart spark-iceberg` and query again.

Test Postgres: user `postgres`, password `secret1234`, database `postgres`, logical replication on.
Write the seed to `<test-dir>/seed.sql` (one `INSERT` per row, ending with a `SELECT count(*)`) and run:

```bash
docker exec -i olake_postgres-test psql -U postgres -d postgres -v ON_ERROR_STOP=1 < <test-dir>/seed.sql
```

## 2. OLake stack

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
- Keep both `environment` blocks always. Drop `APP_ENV` and `CUSTOM_DRIVER_VERSION` when no driver was built.
  Together they make the UI offer the local driver tag and skip its version checks.
- An override, not an edit to `docker-compose-v1.yml`: the compose file may be the user's working copy, or a read-only checkout of a repo that was not built.

The compose file comes from `<olake-ui>`. When olake-ui is not part of the change, use the managed clone at the pinned release tag of `olakego/ui`, so the compose file matches the images.
Start it from the run directory, so the compose file's `${PWD}/olake-data` bind mount lands there and not in the repo:

```bash
cd <run-dir> && docker compose -p olake-dev-<run-id> -f <olake-ui>/docker-compose-v1.yml -f compose.override.yml up -d
```

Deploy gate: <!-- TODO[BEFORE_MERGE]: olake-ui#7 -->

```bash
${CLAUDE_SKILL_DIR}/scripts/compose-gate.sh olake-dev-<run-id> <run-dir>
```

It waits until every service with a healthcheck is healthy, every one-shot service (the migrations, `signup-init`) exited 0 and every other service runs, then logs in and writes `<run-dir>/cookies.txt`.
It ends with `GATE PASS`, or `GATE FAIL: <reason>` and the state of every service.
Then check its `image` lines: the run tag for each built image, the pinned release tag for the others.

## 3. API

Base URL `http://localhost:8000/api/v1/project/olake` (`<api>` below).
Every endpoint, request body and response is in `<olake-ui>/api-contract.md`, in the code under test.
It is about 1,260 lines: list its sections with `grep -n '^###' <olake-ui>/api-contract.md` and read only the section of the call being made.
Keep the cookie jar in `<run-dir>`, and every request and result file in `<test-dir>`.

<!-- TODO[BEFORE_MERGE]: olake-ui#1, olake-ui#2, olake-ui#3, olake-ui#4, olake-ui#5. api-contract.md gaps; until fixed, the login command, api-op.py and errors.md cover them. -->

The deploy gate logs in and writes the cookie jar; pass `-b <run-dir>/cookies.txt` on every later `curl` call.
To log in again (a new stack, or an expired session):

```bash
curl -s -c <run-dir>/cookies.txt -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"password"}' http://localhost:8000/login
```

The test calls, in order: source versions, source and destination spec, source and destination test, discover (`sources/streams` with `job_id` -1), create job, job sync, job tasks.
Run the asynchronous ones with the bundled script, which posts, polls and saves the result:

```bash
python3 -I ${CLAUDE_SKILL_DIR}/scripts/api-op.py <run-dir> sources/test <test-dir>/body-src-test.json <test-dir>/res-src-test.json 120
```

- A spec result holds the JSON schema at `data.spec.jsonschema`.
  The Iceberg writer's keys for each catalog are under `properties.writer.dependencies.catalog_type.oneOf`, one entry per `catalog_type` value.
- For discover, take `available_streams` and `selected_streams` from the result, set `sync_mode` on every selected entry, and send both back as JSON strings on job create.
- Create the job with `frequency` `0 0 1 1 *` and start each run with job sync, so nothing runs on a schedule.
- Use the run tag as the driver `version` when a driver was built (it is listed because of `CUSTOM_DRIVER_VERSION`), otherwise the pinned release tag.

## 4. Connection values

Driver containers run on the default bridge network.
They reach the test stacks through ports published on the host.

| Setting | Value |
| --- | --- |
| Source host, port | `host.docker.internal`, `5433` |
| Catalog | JDBC, `jdbc:postgresql://host.docker.internal:5432/iceberg`, user `iceberg`, password `password` |
| Storage | `http://host.docker.internal:9000`, path style, no SSL, access key `admin`, secret `password`, region `us-east-1` |
| Warehouse path | `s3a://warehouse` |
| Catalog name | `olake_iceberg` (the spec default, and the catalog Spark is configured with) |

Map the values to the key names in the destination spec of the version under test.
Do not copy configs from the olake repo's test data: they carry keys the current spec no longer has (for example `iceberg_db`).

On Linux, `host.docker.internal` does not resolve inside containers by default.
Use the bridge gateway instead: `docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}'`.

## 5. Verify with Spark

```bash
docker exec spark-iceberg /opt/spark/bin/spark-sql -e "SHOW TABLES IN olake_iceberg.<namespace>; DESCRIBE olake_iceberg.<namespace>.<table>; SELECT * FROM olake_iceberg.<namespace>.<table> ORDER BY 1"
```

Put every query of one verify pass in one call: each call starts a JVM, about 10 seconds.
Add `--conf spark.sql.session.timeZone=UTC` so timestamps print in UTC.
`<namespace>` is the stream's `destination_database` from discover with `:` replaced by `_` (for example `orch_baseline_postgres:public` becomes `orch_baseline_postgres_public`).

Dump the source for the comparison with NULL printed as `NULL`, not as an empty string:

```bash
docker exec olake_postgres-test psql -U postgres -d postgres -At -F $'\t' -P null=NULL \
  -c "SET timezone='UTC'; SELECT <columns> FROM <table> ORDER BY 1" > <test-dir>/source-dump.tsv
```

## 6. Logs

Every task writes its files to a workflow directory, `<run-dir>/olake-data/<workflow-dir>/`.
The worker names it from the Temporal workflow ID:

| Task | `<workflow-dir>` | Example |
| --- | --- | --- |
| Spec, test connection, discover, stream difference | The workflow ID | `fetch-spec-postgres-<n>`, `test-connection-olake-<id>`, `discover-catalog-olake-<id>` |
| Sync, clear destination | SHA-256 of the workflow ID `sync-<project>-<job id>-<start time>` | `printf %s 'sync-olake-3-2026-11-12T12:34:03Z' \| shasum -a 256` |

The worker log line `running container` gives it as `containerName`, with the command and the image tag.
Every directory has `logs/worker.log`: the worker's JSON log for that one task, the first file to read when a task fails.
It shows the job name, ID and attempt, the image tag and whether it came from the local cache or a pull, the driver command line, a one-line failure summary, and the persisted state.
A sync directory also has `source.json`, `destination.json`, the streams files, `state.json`, `stats.json` (Synced Records, once written) and `logs/sync_<time>/olake.log`.
The worker removes the driver container when the task ends, so read these files, not `docker logs`.

| What | Command |
| --- | --- |
| Which workflow directory a task used | `docker logs olake-temporal-worker 2>&1 \| grep 'running container' \| cut -c1-250`: `containerName` is `<workflow-dir>` |
| Sync result | `cat <run-dir>/olake-data/<workflow-dir>/stats.json` |
| Sync log | `grep -h -i -E 'error\|fatal\|creating table\|successfully wrote' <run-dir>/olake-data/<workflow-dir>/logs/*/olake.log \| cut -c1-250` |
| One task, from the worker | `grep -h -E '"level":"(error\|warn)"\|running container\|Using image' <run-dir>/olake-data/<workflow-dir>/logs/worker.log \| cut -c1-250` |
| Worker, across tasks (start-up, Temporal connection) | `docker logs --since 10m olake-temporal-worker 2>&1 \| grep -i -E 'error\|fail' \| cut -c1-250` |
| UI and API | `docker logs --since 10m olake-ui 2>&1 \| grep -i -E 'error\|fail' \| cut -c1-250` |

## 7. Stack handoff

When the user tests by hand, give them this, filled in for the stack:

| What | Value |
| --- | --- |
| OLake UI | `http://localhost:8000`, login `admin` / `password` |
| API | `http://localhost:8000/api/v1/project/olake`, cookie login as in section 3 |
| Temporal UI | `http://localhost:8081`, when the stack was started with `--profile debug` |
| Test Postgres | From the host: `localhost:5433`. In the OLake UI: host `host.docker.internal`, port `5433`, user `postgres`, password `secret1234`, database `postgres` |
| Iceberg destination | The values in section 4, entered in the UI form for a JDBC catalog |
| MinIO console | `http://localhost:9001`, `admin` / `password` |
| Spark | `docker exec -it spark-iceberg /opt/spark/bin/spark-sql`, catalog `olake_iceberg`; Spark UI `http://localhost:8088` |
| Driver version to pick in the UI | The run tag, when a driver was built; else the pinned release tag |
| Image tags in use | One line per image |
| Logs | Section 6 |
| Teardown | Section 8 |

## 8. Teardown

```bash
cd <run-dir> && docker compose -p olake-dev-<run-id> -f <olake-ui>/docker-compose-v1.yml -f compose.override.yml down -v
make -C <olake> olake.postgres.teardown
make -C <olake> olake.destination.all.teardown
```

Remove the stack's images only when the user asks: `docker rmi <image>:<tag>`.
