# OLake architecture

What runs where, so the agent knows which part to check, configure or blame.
[OLake architecture deep dive](https://olake.io/blog/olake-architecture-deep-dive).

## OLake Go (the engine)

One binary per source, shipped as the Docker image `olakego/source-<source>`. Each image contains:

| Part | What it does |
| --- | --- |
| Protocol layer (CLI) | The commands `spec`, `check`, `discover`, `sync`, `clear-destination`. Loads `source.json`, `destination.json`, the streams files and `state.json`. |
| Driver (source) | Connects to one source type, discovers streams, reads data: chunked parallel backfill, then incremental or CDC reads. |
| Writer (destination) | Built into every image. Writes the records the driver reads, so reads never block on a separate service. |
| Type system | Maps source types to OLake types, handles schema changes and normalization. |
| State | Tracks per-stream progress (cursors, CDC position, finished backfill chunks) in `state.json`, so a stopped sync resumes. |

### Writers

| Writer | How it writes | Targets |
| --- | --- | --- |
| Iceberg | Go side batches records and sends them over gRPC (port `50051`) to one bundled Java Iceberg writer per sync. Upserts use delete files. | Catalogs: REST, Glue, Hive, JDBC, and others. Storage: S3, MinIO, GCS, Azure. |
| Parquet | Writes Parquet files directly, with partition folders. | Local disk or object storage (S3, GCS, Azure). |

### Data flow of a sync

1. `check`: the driver connects to the source; the writer connects to the catalog and storage.
2. `discover`: the driver lists streams with columns, types, primary keys, cursor fields and supported sync modes.
3. `sync`, for each selected stream:
   - `full_refresh`: split the table into chunks, read them in parallel, write each batch.
   - `incremental` and `cdc`: same backfill first, then read only new changes (cursor or change log).
   - `strict_cdc`: change log only, no backfill.
4. Progress is saved to `state.json` as chunks and changes are committed. `stats.json` shows live counts.

Kafka and S3 sources read offsets and files, not tables: no chunked backfill or change log. See their driver skill.

### Files and logs

| Item | Location |
| --- | --- |
| Config, streams, `state.json`, `stats.json` | The folder passed with `--config` etc. Inside a driver container it is mounted at `/mnt/config`. |
| Logs | `<config folder>/logs/sync_<timestamp>/olake.log`, plus the container's stdout. |

## OLake UI (the platform)

The UI runs the same driver images for you and adds scheduling. Docker compose stack:
[`docker-compose.yml`](https://github.com/datazip-inc/olake-ui/blob/master/docker-compose.yml) in
`datazip-inc/olake-ui`. Images use the `latest` tag and `pull_policy: always`, so every `up` pulls the newest release.

| Service | Role |
| --- | --- |
| `olake-ui` | Web app and API at `http://localhost:8000`: sources, destinations, jobs. |
| `temporal-worker` | Runs each check, discover and sync by launching `olakego/source-<source>` containers through the Docker socket. |
| `temporal` | Workflow engine that schedules and tracks job runs. |
| `temporal-ui` | Web UI to inspect workflow runs, at `http://localhost:8081`. |
| `postgresql` | Stores UI data (users, sources, destinations, jobs) and Temporal data. |
| `elasticsearch` | Temporal visibility store (workflow search). |
| `signup-init` | One-time job that creates the default admin user, then exits. |

- `olake-ui` and `temporal-worker` mount `/var/run/docker.sock`; without it no job can run.
- Job files (configs, streams, state, logs) live on the host in `./olake-data`, bind-mounted at
  `/tmp/olake-config`. Each run's folder is mounted into the driver container at `/mnt/config`.
- Driver containers start on Docker's default network, not `olake-network`. From inside them `localhost` is
  the container itself and compose service names do not resolve: reach a source on the host with
  `host.docker.internal` (Docker Desktop) or the host's IP (Linux).
- `docker compose down -v` deletes the named volumes, including `postgresql` data: every user, job and saved
  state is lost.

On Kubernetes the `olake-helm` chart deploys the same parts; the worker (`olakego/ui-worker`) launches
the driver images as pods, so driver logs are in `kubectl logs <pod>`.

```text
CLI:  user ── docker run ──▶ olakego/source-<source> ──▶ Iceberg / Parquet
UI:   user ──▶ olake-ui ──▶ temporal ──▶ temporal-worker ──▶ olakego/source-<source> ──▶ Iceberg / Parquet
```

## Where to look when something fails

| Symptom | Part to check |
| --- | --- |
| `check` on the source fails | Driver: network (`localhost` from a container, see above), credentials, source prerequisites |
| `check` on the destination fails | Writer: catalog URL, storage endpoint, credentials |
| `discover` finds no streams | Driver: database name, user grants |
| Sync stops during backfill or CDC | Driver and `state.json`; rerun with `--state` |
| Sync fails while writing | Writer: catalog, storage, schema change; for Iceberg, the Java writer lines in `olake.log` |
| UI job never starts | `temporal-worker` logs and the Docker socket mount |
| UI job state unclear | `temporal-ui` at `http://localhost:8081` |

## Related

- OLake Fusion: optional compaction and maintenance for the Iceberg tables OLake writes.
