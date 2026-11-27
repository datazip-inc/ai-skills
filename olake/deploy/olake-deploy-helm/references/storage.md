# Storage (Helm)

The UI, the worker and the job pods share one store for job files: `source.json`,
`destination.json`, `streams.json`, `state.json` and the logs, one folder per run. Pick one with
`global.logFileStorageMode`. Postgres has its own PVC (`postgresql.persistence.size`, default `8Gi`).

| Mode | Value | Default backend | Production backend |
| --- | --- | --- | --- |
| NFS (default, **deprecated**: removed at end of 2026) | `nfs` | In-cluster NFS server, `20Gi` | An RWX StorageClass: EFS, Filestore, Azure Files, CephFS, Longhorn |
| S3 | `s3` | In-cluster MinIO, `20Gi` | AWS S3, GCS (S3 API), external MinIO |

New installs: use S3 mode, unless Fusion is needed (Fusion needs NFS or RWX).

## S3 mode

```yaml
global:
  logFileStorageMode: "s3"

s3LogFileStorage:
  bucket: "olake"
  region: "us-east-1"          # required; MinIO accepts any value
  prefix: ""                   # optional key prefix
  minio:
    enabled: false             # true = in-cluster MinIO (tests)
  external:
    endpoint: ""               # empty for AWS S3; "https://storage.googleapis.com" for GCS
    existingSecret: "s3-log-file-storage-secret"
```

Static keys (GCS: HMAC keys):

```bash
kubectl create secret generic s3-log-file-storage-secret -n olake \
  --from-literal=OLAKE_S3_ACCESS_KEY_ID=<ACCESS_KEY_ID> \
  --from-literal=OLAKE_S3_SECRET_ACCESS_KEY=<SECRET_ACCESS_KEY>
```

AWS IAM instead of keys: `s3LogFileStorage.external.role.enabled: true`. For IRSA add
`eks.amazonaws.com/role-arn` under `s3LogFileStorage.external.role.annotations`; for EKS Pod
Identity leave it empty. The role needs list, get, put and delete on the bucket.

In-cluster MinIO: credentials `s3LogFileStorage.minio.auth.rootUser` / `rootPassword`
(`olake` / `password`). Change the password outside a test.

Layout: `<bucket>/<prefix>/<run folder>/` with the job files and `logs/`. Run folder names:
[logs.md](logs.md#run-folders).

Job pods need driver images `v0.9.2` or later in S3 mode.

## NFS mode

Default: the chart runs an NFS server StatefulSet (`<release>-nfs-server`) and a StorageClass
`nfs-server`, and creates one RWX PVC (`olake-shared-storage`) on it.

```yaml
nfsServer:
  enabled: true
  persistence:
    size: 20Gi                 # backing volume of the NFS server
```

Bring your own RWX StorageClass:

```yaml
nfsServer:
  enabled: false
  external:
    storageClass: "efs-sc"     # efs-sc, filestore-csi, azurefile, rook-cephfs, longhorn
    size: 20Gi
    name: ""                   # existing PVC name; default olake-shared-storage
    deletePVCOnUninstall: false
```

The built-in NFS server does not work on Bottlerocket nodes (EKS). Use EFS or S3 mode there.

The worker mounts the volume at `/data/olake-jobs`, the UI at `/tmp/olake-config`, job pods at
`/mnt/config` (their run folder).

## Disk use

- `olakeWorker.env.LOG_RETENTION_PERIOD` (days, default `30`): the worker deletes run folders older
  than that, daily, in both modes.
- Per-job index PVCs (`olake-index-<JobID>`) are separate and never deleted by the worker:
  [values.md](values.md#per-job-index-volumes).

## What survives uninstall

`helm uninstall` keeps:

- The shared PVC (`helm.sh/resource-policy: keep`), unless `nfsServer.external.deletePVCOnUninstall`.
- NFS server components: StatefulSet, Service, ServiceAccount, StorageClass `nfs-server`,
  ClusterRole and ClusterRoleBinding `olake-nfs-server`.
- Per-job index PVCs `olake-index-<JobID>`.
- PVs in `Released` state, by the StorageClass reclaim policy.
- The S3 bucket and its objects.

A reinstall with the same release and namespace reuses them. Full removal follows
[`UNINSTALL_GUIDE.md`](https://github.com/datazip-inc/olake-helm/blob/v0.5.1/helm/olake/UNINSTALL_GUIDE.md)
or its `uninstall.sh` (`--keep-pvcs`, `--keep-namespace`). Every one of those deletes is
irreversible: list what will go (`kubectl get pvc,pv,sc -n olake`), confirm with the user, and back up
first.

## Backup

- Postgres: `kubectl exec -n olake postgresql-0 -- pg_dumpall -U temporal > olake-db.sql`. Holds
  sources, destinations, jobs and users (configs encrypted if a key is set).
- Shared storage: copy the run folders (`kubectl cp` from the worker pod at `/data/olake-jobs`, or
  sync the bucket). Holds `state.json` per job.
- Keep the encryption key with the backup.
