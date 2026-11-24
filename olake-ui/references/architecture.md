# How OLake UI runs a task

Shared by every skill in this plugin.
Read from olake-ui v0.9.3 (`server/internal/services/temporal/`) and the worker in olake-helm v0.5.1 (`worker/temporal/`, `worker/database/`, `worker/executor/`).

## Flow

```text
browser or API client
        │  HTTP :8000
        ▼
   olake-ui ──────────── reads and writes ────────────▶ ┌──────────────────────────┐
        │  1. writes the task's configs                 │ OLake database           │
        │     into its job folder                       │ (postgresql service)     │
        │  2. starts a Temporal workflow                │ users, sources,          │
        │     (task queue OLAKE_DOCKER_TASK_QUEUE)      │ destinations, jobs,      │
        ▼                                               │ each job's sync state    │
   temporal                                             └──────────────────────────┘
        │                                                            ▲
        ▼                                                            │
   temporal-worker ──── reads the job, writes its sync state ────────┘
        │  3. starts the driver olakego/source-<driver>:<version>
        │     with the job folder mounted (compose: a container through
        │     the host's Docker socket; Kubernetes: a pod)
        ▼
   driver: spec | check | discover | sync
        │  4. writes streams, state.json, stats.json and its log into the job folder
        ▼
   olake-ui reads the result from the job folder, and the status from Temporal
```

| Workflow | Started by | Runs |
| --- | --- | --- |
| `ExecuteWorkflow` | Spec, test connection, discover, stream difference | One driver command; no retry |
| `RunSyncWorkflow` | A job's schedule `schedule-sync-<project>-<job id>`, or a manual sync | The sync, then the state update in the database |
| `IndicatorWorkflow` | GitOps, on a reconcile that failed for good | A marker container or pod that shows the failure |

The worker also posts usage-stats events to olake-ui (`/internal/worker/callback/sync-telemetry`); that is not how status travels.

## Where state lives

| What | Where | Lost by |
| --- | --- | --- |
| Users, sources, destinations, jobs, each job's sync state | OLake database, in the `postgresql` service (database `postgres`) | `down -v` on compose; deleting the database volume on Kubernetes |
| Task files: configs, streams, `state.json`, `stats.json`, logs | Job folder: `olake-data/` on compose (`/tmp/olake-config` in the containers), `/data/olake-jobs` on Kubernetes, or an S3 bucket in S3 log mode | Deleting the folder or the bucket |
| Workflow history and schedules | Temporal, in the same `postgresql` service | `down -v` |

## Job folder names

| Task | Folder |
| --- | --- |
| Spec, test connection, discover | The workflow ID, `<kind>-<project>-<hex>`, for example `discover-catalog-123-8f14e45f...`; the API returns it as `operation_id` |
| Sync, clear destination | The SHA-256 of the run's workflow ID, `sync-<project>-<job id>-<start time>` |

## Why some settings go on two services

| Setting | `olake-ui` needs it to | `temporal-worker` needs it to |
| --- | --- | --- |
| Encryption key `OLAKE_SECRET_KEY` | Encrypt and read configs it stores | Decrypt the job it reads from the database before a sync |
| Data folder (`PERSISTENT_DIR` and the bind mount) | Write a task's configs and read its results | Mount the same host folder into each driver container |
| S3 log mode (`OLAKE_STORAGE_MODE`, `OLAKE_S3_*`) | Write configs to and read results from the bucket | Have each driver read and write the bucket |
| Registry (`CONTAINER_REGISTRY_*`) | List the driver versions the UI offers | Pull the driver image |

## Security

On compose the worker, and the UI, mount the host's Docker socket: they can start any container on the host.
Run the stack on a machine where that is acceptable, and keep port 8000 off the public internet.
