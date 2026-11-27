# Helm values

The values used most often, from [olake-helm `v0.5.1`](https://github.com/datazip-inc/olake-helm/blob/v0.5.1/helm/olake/values.yaml).
Every key: [`OLAKE_README.md`](https://github.com/datazip-inc/olake-helm/blob/v0.5.1/helm/olake/OLAKE_README.md).
Apply a change with `helm upgrade olake olake/olake -n olake -f values.yaml`.

## Starting point

```yaml
global:
  storageClass: ""            # "" = cluster default; e.g. gp3, standard-rwo, managed-csi
  env:
    OLAKE_SECRET_KEY: "<PASSPHRASE_OR_KMS_ARN>"

olakeUI:
  image:
    tag: "<UI_TAG>"           # pin in production; default latest
  initUser:
    enabled: true
    existingSecret: "olake-admin"   # keys: username, password, email

olakeWorker:
  image:
    tag: "<WORKER_TAG>"
```

Storage settings: [storage.md](storage.md). UI access: [ports.md](ports.md).

## Admin user

`olakeUI.initUser.adminUser` (`admin` / `password` / `admin@example.com`) is used only without
`existingSecret`. Map other key names with `olakeUI.initUser.secretKeys`. The `olake-signup-init` job
creates the user once; later changes do not reset the password.

## Encryption

`global.env.OLAKE_SECRET_KEY`: an AWS KMS key ARN (`arn:aws:kms:...`), any other string (hashed to a
256-bit key), or `""` (no encryption). Set it before the first config is saved, and keep it: configs
saved under one key cannot be read with another.

## Global environment

`global.env` goes to every OLake component (UI and worker). `olakeUI.env` and `olakeWorker.env`
override it per component.

## Private registry

```yaml
global:
  imagePullSecrets:
    - <PULL_SECRET>               # kubectl create secret docker-registry ...
  env:
    CONTAINER_REGISTRY_BASE: "registry.example.com/myproject"
```

`CONTAINER_REGISTRY_BASE` prefixes every image in the chart and the driver images of job pods.
`imagePullSecrets` also applies to job pods. Mirror all images first, including each
`olakego/source-<driver>` the jobs use.

## Job pods

Scheduling and size per job ID (shown in the jobs list in the UI). Profile `0` is the default for
unmapped jobs and for test, discover and spec pods.

```yaml
global:
  jobProfiles:
    0:
      resources:
        requests: { cpu: "500m", memory: "1Gi" }
        limits: { memory: "2Gi" }
    123:                                 # JobID
      nodeSelector:
        olake.io/workload-type: "heavy"
      tolerations:
        - { key: "heavy-workload", operator: "Equal", value: "true", effect: "NoSchedule" }
      resources:
        requests: { cpu: "4", memory: "8Gi" }
        limits: { memory: "8Gi" }
```

- Built-in default without a profile: requests `256Mi` and `100m`, no limits.
- `resources` replace the fallback as a whole; fields are not merged.
- Sync and clear destination use profile `<JobID>`, then `0`, then the default. Test and discover use
  `0`, then the default.
- Changes apply on the next run after `helm upgrade`, without a worker restart.
- `olakeWorker.resources` sizes the worker pod only, not job pods.
- `global.jobPodLabels` and `global.podAnnotations` add labels and annotations to job pods (internal
  `olake.io/*` labels win).

## Cloud IAM for job pods

Job pods use `global.jobServiceAccount`. Bind it to a cloud role instead of keys in the configs:

```yaml
global:
  jobServiceAccount:
    create: true
    name: "olake-job-sa"
    annotations:
      eks.amazonaws.com/role-arn: "arn:aws:iam::<ACCOUNT>:role/<ROLE>"           # AWS IRSA
      # iam.gke.io/gcp-service-account: "<SA>@<PROJECT>.iam.gserviceaccount.com"  # GKE
      # azure.workload.identity/client-id: "<CLIENT_ID>"                         # AKS
  jobPodLabels:
    azure.workload.identity/use: "true"   # AKS Workload Identity only
```

The cloud side (trust policy, workload identity binding to `olake/olake-job-sa`) is set up by the
user's cloud admin. Then leave the access keys empty in the destination config.

## Files in job pods

CA bundles, client keys or keytabs, from ConfigMaps or Secrets in the release namespace:

```yaml
global:
  extraJobVolumes:
    - name: custom-ca
      configMap:
        name: my-ca-certs
  extraJobVolumeMounts:
    - name: custom-ca
      mountPath: /etc/ssl/custom-certs
```

The file is then `/etc/ssl/custom-certs/<key>`. In the connector config use `cert_source: "path"` and
the `*_path` field. Mounts are read-only; `mountPath` must be unique, not `/`, not inside
`/mnt/config`, and not over `/etc/ssl/certs`.

## Per-job index volumes

Jobs with Iceberg positional deletes or deletion vectors (`index_required`) get a PVC
`olake-index-<JobID>`, kept across runs and never deleted by the worker.

```yaml
jobIndexes:
  default:
    size: 50Gi            # default 20Gi; grow-only
    storageClass: "gp3"   # block storage; not NFS, EFS or Azure Files
  jobs:
    123:
      size: 200Gi
```

## External Postgres

```yaml
postgresql:
  enabled: false
  external:
    existingSecret: "olake-postgres"
```

The Secret holds `host`, `port`, `username`, `password`, `ssl_mode`, `olake_database`,
`temporal_database` and `fusion_database` (key names mappable with `postgresql.external.secretKeys`).
`postgresql.external.properties` sets the same fields inline, for GitOps.

## External Temporal

```yaml
temporal:
  enabled: false
  external:
    existingSecret: "olake-temporal"
```

Keys: `TEMPORAL_ADDRESS`, `TEMPORAL_API_KEY`, `TEMPORAL_ENABLE_TLS`, `TEMPORAL_EXTERNAL`,
`TEMPORAL_NAMESPACE`, `TEMPORAL_TASK_QUEUE`.

## Optional components

| Value | Default | Adds |
| --- | --- | --- |
| `temporal.ui.enabled` | `false` | Temporal Web UI, Service `temporal-ui` on `8081`. |
| `fusion.enabled` | `false` | Fusion compaction. Needs NFS or RWX storage, not S3 mode. |
| `elasticsearch.enabled` | `false` | Legacy Temporal visibility store. |
| `gitops.enabled` | `false` | Sources, destinations and jobs from labelled ConfigMaps ([gitops.md](https://github.com/datazip-inc/olake-helm/blob/v0.5.1/helm/olake/docs/gitops.md)). |
