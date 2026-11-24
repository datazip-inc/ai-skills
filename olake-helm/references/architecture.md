# How OLake runs on Kubernetes



## Workloads

| Workload | Kind | Role |
| --- | --- | --- |
| `olake-ui` | Deployment, Service port 8000 | Web UI and REST API |
| `olake-workers` | Deployment, Service port 8090 | Runs each task as a pod of its own |
| `temporal` | Deployment, Service port 7233 | Workflow engine; off with `temporal.enabled: false` for an external Temporal |
| `postgresql` | StatefulSet, Service port 5432 | The OLake database and Temporal's; off with `postgresql.enabled: false` for an external Postgres |
| `olake-minio` | StatefulSet | In-cluster S3 for task files, only in S3 mode with `s3LogFileStorage.minio.enabled: true` |
| `olake-nfs-server` | StatefulSet, StorageClass `nfs-server` | In-cluster NFS for task files, only in NFS mode with `nfsServer.enabled: true` |
| `olake-signup-init` | Job | Creates the admin user; deleted an hour after it finishes |
| `olake-post-install-wait` | Helm hook Job | Waits for the services after the first install, then is deleted |
| `temporal-ui`, `elasticsearch`, Fusion | Optional | Off by default |

## Flow

```text
browser or API client
        │  port-forward, Ingress or a LoadBalancer Service, to olake-ui :8000
        ▼
   olake-ui ── reads and writes ──▶ postgresql (OLake database: users, sources, destinations, jobs, sync state)
        │  1. writes the task's configs to the shared task storage
        │  2. starts a Temporal workflow
        ▼
   temporal
        ▼
   olake-workers ── reads the job, writes its sync state ──▶ postgresql
        │  3. creates one pod for the task, from olakego/source-<driver>:<version>,
        │     with the shared task storage mounted and the job service account
        ▼
   task pod: spec | check | discover | sync
        │  4. writes streams, state.json, stats.json and its log to the shared task storage
        ▼
   olake-workers deletes the pod; olake-ui reads the result from the task storage, and the status from Temporal
```

## Task storage

`global.logFileStorageMode` picks one shared store for task files:

| Mode | Store | Where a task's files are |
| --- | --- | --- |
| `nfs` (the chart default, deprecated: removed at the end of 2026) | A ReadWriteMany volume, `olake-shared-storage`, from the in-cluster NFS server or an RWX StorageClass (EFS, Filestore, Azure Files) | `/data/olake-jobs/<task folder>/` in the worker pod |
| `s3` | A bucket: the in-cluster MinIO, or AWS S3, GCS or another S3-compatible store | `<bucket>/<prefix>/<task folder>/`, logs in chunks under `logs/` |

The task folder is named as on docker compose: the workflow ID for spec, test connection and discover, and the SHA-256 of `sync-<project>-<job id>-<start time>` for a sync.
The worker deletes each task pod when the task ends, so the task folder is the record, not `kubectl logs`.

## Where state lives

| What | Where | Lost by |
| --- | --- | --- |
| Users, sources, destinations, jobs, each job's sync state, Temporal history and schedules | The `postgresql` StatefulSet's volume, or the external Postgres | Deleting that PVC or the external database |
| Task files | The shared volume or the bucket | Deleting the `olake-shared-storage` PVC or the bucket |
| Iceberg positional-delete index of a job | A PVC per job, `olake-index-<job id>`, only for jobs with `index_required` | Deleting that PVC; the next sync rebuilds it |

`helm uninstall` keeps every one of these: the StatefulSet volumes are never deleted by Helm, and the shared storage and NFS objects carry `helm.sh/resource-policy: keep`.

## Settings that reach every pod

`global.env` is set on `olake-ui` and `olake-workers`, and stored in the ConfigMap `olake-global-env`, which the worker passes on to every task pod.
So one entry sets a value for all three: the encryption key `OLAKE_SECRET_KEY`, `CONTAINER_REGISTRY_BASE`, `TELEMETRY_DISABLED`.
Anyone who can read ConfigMaps in the namespace can read these values.
`olakeUI.env` and `olakeWorker.env` set a value for one Deployment only.
