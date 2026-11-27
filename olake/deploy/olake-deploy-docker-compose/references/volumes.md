# Volumes and data (docker compose)

## What is stored where

| Storage | Type | Holds | Removed by |
| --- | --- | --- | --- |
| `./olake-data` (`${PWD}/olake-data`) | Bind mount at `/tmp/olake-config` in `olake-ui` and `temporal-worker` | One folder per run: configs, `streams.json`, `state.json`, logs; per-job index under `index/` | `rm -rf ./olake-data` only |
| `temporal-postgresql-data` | Named volume | OLake database (sources, destinations, jobs, users) and Temporal data (run history) | `docker compose down -v` |
| `./amoro-logs` | Bind mount | Fusion logs | `fusion` profile only |
| `temporal-elasticsearch-data` | Named volume | Run history | Legacy `docker-compose.yml` only |

Named volumes get the compose project name as prefix (for example `<folder>_temporal-postgresql-data`).
List them with `docker volume ls`.

## Run folders in `./olake-data`

Each driver container mounts its run folder at `/mnt/config`.

| Run | Folder name |
| --- | --- |
| Test connection, discover | The Temporal workflow ID. |
| Sync, clear destination | `sha256` hex of the workflow ID. For a sync it is `sync-<projectID>-<jobID>`. |

Find a job's sync folder from the job ID (the project ID is `123` in this release):

```bash
printf '%s' "sync-123-<JOB_ID>" | shasum -a 256 | cut -d' ' -f1
```

Inside: `source.json`, `destination.json`, `streams.json`, `state.json` and
`logs/sync_<timestamp>/olake.log`. These are the same files as a CLI run (`olake-protocol`), so a
failing job can be rerun from the CLI with them. Config files can hold credentials: do not print them;
read only the fields needed.

## Backup

Stop the stack, then copy both stores:

```bash
docker compose stop
tar czf olake-data-backup.tgz ./olake-data
docker run --rm -v <PROJECT>_temporal-postgresql-data:/data -v "$PWD":/backup alpine \
  tar czf /backup/temporal-postgresql-data.tgz -C /data .
docker compose start
```

Restore is the reverse into an empty volume and folder. Keep the encryption key with the backup:
saved configs cannot be read without it.

## Disk use

- Logs: `LOG_RETENTION_PERIOD` (days, default 30) on `temporal-worker` ([config.md](config.md#retention-on-temporal-worker)).
- Driver images: one per driver and version; `docker image ls olakego/*`. Remove unused tags with the
  user's yes.
- Stopped driver containers: list with `docker ps -a --filter name=<RUN_FOLDER>`; remove by name.
