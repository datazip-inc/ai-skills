# Values

Every setting goes in `~/olake-helm/values.yaml`, passed with `-f` on every `helm install` and `helm upgrade`.
Never edit the chart's own `values.yaml`.
Read from the chart `olake-0.0.36`: `helm/olake/values.yaml`, `README.md` and `templates/`.
The chart documents every key: `helm show values olake/olake --version <chart-version>`, and the guide `helm show readme olake/olake --version <chart-version>`.

The values file can hold secrets (the encryption key, passwords): keep it at mode 0600 and out of any repository, or put the secrets in Kubernetes Secrets where a key below allows it.

## Images

The chart's tags are `latest` with `pullPolicy: Always`; pin them:

```yaml
olakeUI:
  image:
    tag: <ui-tag>
    pullPolicy: IfNotPresent
olakeWorker:
  image:
    tag: <worker-tag>
    pullPolicy: IfNotPresent
```

## Task storage

One store for task files (configs, state, stats, logs), picked by `global.logFileStorageMode`.
NFS is the chart's default, but deprecated: it is removed at the end of 2026.
S3 mode needs the source drivers at v0.12.0 or later (the worker refuses older ones: `connector version <v> does not support S3 storage mode: requires v0.12.0 or later`), and does not work with Fusion.
Pick the mode at install: neither the chart nor the worker moves existing task files when it changes.

### S3 with the in-cluster MinIO (trial)

```yaml
global:
  logFileStorageMode: s3
s3LogFileStorage:
  minio:
    auth:
      rootPassword: <password>      # the default is "password"
```

MinIO runs as one pod: a single point of failure, not for production.

### S3 in an external bucket (production)

Create the bucket first. With static keys, create the Secret before the install:

```bash
kubectl --kubeconfig ~/olake-helm/kubeconfig create namespace olake
kubectl --kubeconfig ~/olake-helm/kubeconfig -n olake create secret generic s3-log-file-storage-secret \
  --from-literal=OLAKE_S3_ACCESS_KEY_ID=<access key id> \
  --from-literal=OLAKE_S3_SECRET_ACCESS_KEY=<secret access key>
```

```yaml
global:
  logFileStorageMode: s3
s3LogFileStorage:
  bucket: <bucket>
  region: <region>
  prefix: ""                        # optional key prefix
  minio:
    enabled: false
  external:
    endpoint: ""                    # empty for AWS S3; set for GCS (https://storage.googleapis.com, HMAC keys) or another S3-compatible store
    existingSecret: s3-log-file-storage-secret
```

On EKS, an IAM role can replace the keys: drop `existingSecret`, and set `external.role.enabled: true`; for IRSA, add the role under `external.role.annotations`:

```yaml
s3LogFileStorage:
  external:
    role:
      enabled: true
      annotations:
        eks.amazonaws.com/role-arn: arn:aws:iam::<account>:role/<role>
```

### NFS

The in-cluster NFS server is on by default in `nfs` mode; it is one pod, needs the `DAC_READ_SEARCH` capability, and does not run on Bottlerocket nodes.
For production NFS mode, use a managed ReadWriteMany StorageClass (EFS, Filestore, Azure Files) instead:

```yaml
global:
  logFileStorageMode: nfs
nfsServer:
  enabled: false
  external:
    storageClass: <rwx storage class>
```

## Encryption key for stored configs

`OLAKE_SECRET_KEY` encrypts the source and destination configs in the OLake database.

| Value | Mode |
| --- | --- |
| `""` (the default) | No encryption. Development only |
| Starts with `arn:aws:kms:` | AWS KMS; the UI and the worker need AWS credentials that may use that key |
| Any other string | AES-256-GCM, with a key derived from the string |

```yaml
global:
  env:
    OLAKE_SECRET_KEY: <key or KMS key ARN>
```

Set it before the first source is created, and never change it afterwards: configs saved under the old key can no longer be read.
`global.env` is stored in the ConfigMap `olake-global-env`, so anyone who can read ConfigMaps in the namespace can read an AES key; a KMS key ARN is not a secret on its own.
Keep a copy of the key outside the cluster.

## Admin user

Set it before the first install: `olake-signup-init` creates the user once, on an empty database.
Keep the password in a Secret, not in the values file:

```bash
kubectl --kubeconfig ~/olake-helm/kubeconfig -n olake create secret generic olake-admin-credentials \
  --from-literal=username='<user>' --from-literal=password='<password>' --from-literal=email='<email>'
```

```yaml
olakeUI:
  initUser:
    existingSecret: olake-admin-credentials
```

## Access to the UI

Port-forward needs nothing in the values.
For an Ingress (any controller; this example is ingress-nginx):

```yaml
olakeUI:
  ingress:
    enabled: true
    className: nginx
    hosts:
      - host: olake.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: olake-tls
        hosts:
          - olake.example.com
```

Or a Service of another type: `olakeUI.service.type: LoadBalancer`, or `NodePort` with `olakeUI.service.nodePort`.
Either one puts the login page on a network: change the admin password first.

## Built-in Postgres

The built-in Postgres holds the OLake database and Temporal's.
Change its password before the first install, and size its volume for the expected jobs and Temporal history:

```yaml
postgresql:
  auth:
    postgresPassword: <password>      # the default is "temporal"; postgresUser stays "temporal"
  persistence:
    size: 20Gi                        # the default is 8Gi; on global.storageClass
```

It is one pod with no replica: for production, an external Postgres (next section) with its own backups.

## External Postgres

Postgres 12 or later, with the `btree_gin` extension, and two databases created first: one for OLake, one for Temporal.
`properties` works with Argo CD and other tools that render with `helm template`; `existingSecret` does not, for Temporal's TLS settings.

```yaml
postgresql:
  enabled: false
  external:
    properties:
      host: <host>
      port: 5432
      username: <user>
      password: <password>
      olake_database: <olake db>
      temporal_database: <temporal db>
      ssl_mode: require
```

With `existingSecret: <secret>` instead of `properties`, the Secret holds the same keys (`host`, `port`, `olake_database`, `temporal_database`, `username`, `password`, `ssl_mode`).

## External Temporal

For Temporal Cloud or a self-hosted Temporal:

```yaml
temporal:
  enabled: false
  external:
    properties:
      TEMPORAL_ADDRESS: <region>.<cloud>.api.temporal.io:7233
      TEMPORAL_API_KEY: <api key>
      TEMPORAL_ENABLE_TLS: "true"
      TEMPORAL_EXTERNAL: "true"
      TEMPORAL_NAMESPACE: <namespace>
      TEMPORAL_TASK_QUEUE: <task queue>
```

`existingSecret: <secret>` with the same keys works too.

## Private registry

`CONTAINER_REGISTRY_BASE` is put in front of every image the chart and the worker use, the driver images too.
Mirror the images first: `olakego/ui`, `olakego/ui-worker`, every `olakego/source-<driver>` the jobs use, `temporalio/server:1.32.0`, `temporalio/admin-tools:1.32.0`, `library/postgres:14-alpine`, `curlimages/curl:8.1.2`, `curlimages/curl:latest`, `library/busybox:latest`, and when used `olakego/minio`, `sig-storage/nfs-provisioner:v4.0.8` and `temporalio/ui:2.16.2`.
`helm template olake olake/olake --version <chart-version> -n olake -f ~/olake-helm/values.yaml | grep -E '^\s+image: ' | sort -u` lists the chart's images for the values in use; the driver images come on top.
For a registry with a login, create a `docker-registry` Secret and list it; `jobServiceAccount.create: true` (the default) passes it on to task pods:

```yaml
global:
  env:
    CONTAINER_REGISTRY_BASE: registry.example.com/myproject
  imagePullSecrets:
    - name: my-registry-secret
  jobServiceAccount:
    create: true
```

## Cloud IAM for task pods

Task pods reach AWS Glue, S3 or cloud catalogs with the job service account's IAM role, instead of keys in the destination config:

```yaml
global:
  jobServiceAccount:
    create: true
    name: olake-job-sa
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::<account>:role/<role>                # AWS IRSA
      # iam.gke.io/gcp-service-account: <sa>@<project>.iam.gserviceaccount.com     # GCP Workload Identity
      # azure.workload.identity/client-id: <client id>                              # Azure Workload Identity
  jobPodLabels:
    azure.workload.identity/use: "true"                                              # Azure only
```

## Node placement and resources for jobs

`global.jobProfiles` is keyed by job ID (shown in the Jobs page); profile `0` is the default for unmapped jobs and for test, discover and spec.
Without any profile, a task pod requests 256 MiB and 100m CPU with no limit.

```yaml
global:
  jobProfiles:
    0:
      resources:
        requests:
          cpu: "500m"
          memory: 1Gi
        limits:
          memory: 2Gi
    123:
      nodeSelector:
        olake.io/workload-type: heavy
      tolerations:
        - key: heavy-workload
          operator: Equal
          value: "true"
          effect: NoSchedule
      resources:
        requests:
          cpu: "2"
          memory: 8Gi
        limits:
          memory: 8Gi
```

- A profile's `resources` replace the fallback as a whole; a profile without `resources` uses profile `0`, then the built-in default.
- Set a memory request on every profile; leave CPU limits unset unless a hard cap is needed.
- Changes apply on each job's next run after `helm upgrade`.
- `global.jobMapping` is the deprecated, nodeSelector-only form; use `jobProfiles`.

## Job index storage

A job with `index_required` (any stream that upserts with positional deletes or deletion vectors) gets its own volume, `olake-index-<job id>`, which the worker never deletes.
It must be block storage (EBS, Persistent Disk), never NFS or EFS.
The worker defaults are 20 GiB on the cluster's default StorageClass; change them under `jobIndexes`:

```yaml
jobIndexes:
  default:
    size: 50Gi                      # grow-only; the StorageClass needs allowVolumeExpansion
    storageClass: gp3
  jobs:
    123:
      size: 100Gi
```

The volume stays in one availability zone: keep that job's placement (`jobProfiles`) in the same zone.

## Custom CA for the UI and the worker

Behind a TLS-inspecting proxy, add the proxy's CA as one file next to the image's own CAs:

```bash
kubectl --kubeconfig ~/olake-helm/kubeconfig -n olake create configmap custom-ca --from-file=ca.crt=./ca.crt
```

```yaml
olakeUI:
  extraVolumes:
    - name: custom-ca
      configMap:
        name: custom-ca
  extraVolumeMounts:
    - name: custom-ca
      mountPath: /etc/ssl/certs/custom-ca.crt
      subPath: ca.crt
      readOnly: true
```

The same under `olakeWorker` adds it to the worker.
Keep `subPath`: a mount over the whole `/etc/ssl/certs` hides the default CAs.

## Certificates and keys for task pods

A driver that needs a CA or a client key reads it from a ConfigMap or Secret mounted into each task pod:

```yaml
global:
  extraJobVolumes:
    - name: custom-ca
      configMap:
        name: my-ca-certs
    - name: client-key
      secret:
        secretName: my-client-key
  extraJobVolumeMounts:
    - name: custom-ca
      mountPath: /etc/ssl/custom-certs
    - name: client-key
      mountPath: /etc/ssl/client-key
```

Each key of the ConfigMap or Secret becomes a file in the mount, for example `/etc/ssl/custom-certs/ca.crt`, which the source or destination config names (for SSL, with `cert_source: path`).
The mounts are read-only, and must not be `/`, `/etc/ssl/certs`, or inside `/mnt/config`.

## Usage stats

```yaml
global:
  env:
    TELEMETRY_DISABLED: "true"
```

## Temporal UI

```yaml
temporal:
  ui:
    enabled: true
    service:
      type: ClusterIP
```

Chart 0.0.36 needs `service.type` too: with `enabled: true` alone, the render fails with `nil pointer evaluating interface {}.annotations`.
Then run `kubectl --kubeconfig ~/olake-helm/kubeconfig -n olake port-forward svc/temporal-ui 8081:8081`, and open `http://localhost:8081`.
