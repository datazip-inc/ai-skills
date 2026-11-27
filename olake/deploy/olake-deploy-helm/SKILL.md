---
name: olake-deploy-helm
description: "Run OLake UI on Kubernetes (EKS, GKE, AKS) with the olake-helm chart: install, values, UI access, NFS or S3 storage, job pod resources and cloud IAM, logs, upgrade, uninstall. Use for a Kubernetes install, or when olake pods or job pods fail."
metadata:
  parent: olake-protocol
  status: experimental
---

# OLake on Kubernetes (Helm)

The chart deploys the OLake UI, the `olake-workers` deployment, Temporal and Postgres. For each
`check`, `discover`, `sync` and `clear-destination`, the worker creates one pod from
`olakego/source-<driver>` and deletes it when the run ends. Job files and logs go to shared storage
(NFS volume or S3 bucket). The CLI flow without a cluster is in `olake-protocol`.

Pinned to [olake-helm `v0.5.1`](https://github.com/datazip-inc/olake-helm/tree/v0.5.1/helm/olake)
(chart `0.0.35`). Value reference: [`OLAKE_README.md`](https://github.com/datazip-inc/olake-helm/blob/v0.5.1/helm/olake/OLAKE_README.md).
The images use the `latest` tag unless the values pin one.

## When to use

- Deploy OLake on a Kubernetes cluster (EKS, GKE, AKS, self-managed, kind or minikube for tests).
- An OLake pod or a job pod fails to start, stays `Pending`, or cannot reach a source.
- Upgrade or uninstall a Helm release.
- Not covered: one machine with Docker → `olake-deploy-docker-compose`; source and destination
  settings → the driver and destination skills.

## Inputs to collect

| Input | Default | Ask when |
| --- | --- | --- |
| Cluster and `kubectl` context | current context | Always: `kubectl config current-context`. |
| Namespace, release name | `olake`, `olake` | Always. |
| StorageClass | cluster default | No default StorageClass, or the user wants a specific one. |
| Shared storage | NFS server in the cluster | Production: S3 bucket or an RWX StorageClass ([references/storage.md](references/storage.md)). |
| Admin user | `admin` / `password` | Anything beyond a test. Use a Secret. |
| Encryption key | none | Anything beyond a test: passphrase or AWS KMS ARN. |
| UI access | port-forward | Users need a URL: ingress host, class, TLS secret. |
| Cloud access for jobs | none | Jobs use S3, Glue, GCS or Azure with IAM roles instead of keys. |
| External Postgres, Temporal | in-cluster | The user has managed ones. |

## Prerequisites

- [ ] Kubernetes 1.19+, Helm 3.2.0+, `kubectl` on the right context.
- [ ] A StorageClass for Postgres and storage volumes: `kubectl get storageclass`.
- [ ] Capacity, per component: UI, Temporal, worker, Postgres 2 vCPU and 4 GB each; each sync pod
      4 vCPU and 8 GB (more for large tables).
- [ ] Nodes can pull `olakego/*` images, or a mirror is set ([references/values.md](references/values.md#private-registry)).
- [ ] Job pods can reach the sources, catalogs and storage (network policies, security groups):
      [references/ports.md](references/ports.md#what-job-pods-need).
- [ ] AWS EKS on Bottlerocket nodes: the built-in NFS server does not work. Use S3 mode or EFS.

## Steps

1. Add the repo:
   ```bash
   helm repo add olake https://datazip-inc.github.io/olake-helm
   helm repo update
   ```
2. Write `values.yaml`. Start from [references/values.md](references/values.md); at least the admin
   Secret and the encryption key for anything beyond a test. Pick shared storage in
   [references/storage.md](references/storage.md). Show the user the file before install.
3. Create the Secrets the values name, in the release namespace:
   ```bash
   kubectl create namespace olake
   kubectl create secret generic olake-admin -n olake \
     --from-literal=username=<ADMIN_USER> --from-literal=password=<ADMIN_PASSWORD> \
     --from-literal=email=<ADMIN_EMAIL>
   ```
4. Render and check, then install:
   ```bash
   helm template olake olake/olake -n olake -f values.yaml > /dev/null
   helm install olake olake/olake -n olake -f values.yaml
   ```
   Quick test with defaults: `helm install olake olake/olake -n olake --create-namespace`.
5. Wait for the pods: `kubectl get pods -n olake -w`. Temporal runs schema setup in init containers
   first. The `olake-signup-init` job creates the admin user.
6. Open the UI: `kubectl port-forward -n olake svc/olake-ui 8000:8000`, then `http://localhost:8000`.
   Ingress and other options: [references/ports.md](references/ports.md).
7. Create a source, destination and job in the UI. Run a test connection and watch the job pod:
   `kubectl get pods -n olake -l app.kubernetes.io/managed-by=olake-workers -w`.

## Verify

- `kubectl get pods -n olake`: `olake-ui`, `olake-workers`, `temporal`, `postgresql` (and
  `nfs-server` or `minio` by storage mode) are `Running` and ready.
- `kubectl get jobs -n olake`: `olake-signup-init` completed.
- `helm status olake -n olake` shows `deployed`.
- A test connection in the UI creates a pod labelled `olake.io/operation-type=check`, which completes
  and goes away; the UI shows success.
- After the first sync, the job's log folder exists on shared storage ([references/logs.md](references/logs.md)).

## Upgrade

```bash
helm repo update
helm diff upgrade olake olake/olake -n olake -f values.yaml   # if the helm-diff plugin is installed
helm upgrade olake olake/olake -n olake -f values.yaml
```

New `latest` images without a chart change: `kubectl rollout restart deployment/olake-ui
deployment/olake-workers -n olake`. Upgrade between runs when possible: a restart of `olake-workers`
during a sync makes Temporal retry the run.

Pin `olakeUI.image.tag` and `olakeWorker.image.tag` in production, so a pod restart cannot change the
version.

## Uninstall

```bash
helm uninstall olake -n olake
```

What stays after uninstall: [references/storage.md](references/storage.md#what-survives-uninstall).
Deleting the PVCs, the NFS components or the namespace deletes job state, history and every config.
Confirm with the user, one step at a time, and offer a backup first.

## Common errors

| Symptom | Cause | Fix |
| --- | --- | --- |
| Pods `Pending`, PVC `Pending` | No default StorageClass, or no RWX class for shared storage | Set `global.storageClass`, or switch storage mode ([storage.md](references/storage.md)). |
| `nfs-server` pod fails on EKS | Bottlerocket nodes | S3 mode or EFS. |
| `ImagePullBackOff` | No access to Docker Hub, or missing pull secret | Mirror images, set `global.imagePullSecrets` and `CONTAINER_REGISTRY_BASE`. |
| Job pod `Pending` | `jobProfiles` selector or resources match no node | `kubectl describe pod`; fix the profile ([values.md](references/values.md#job-pods)). |
| Job pod `OOMKilled` | Sync pod too small | Raise `global.jobProfiles.<JobID>.resources`. |
| Test connection times out | Network policy, security group, or private DNS from the job pod | Test from a debug pod in the namespace ([ports.md](references/ports.md#what-job-pods-need)). |
| Job pod gets `AccessDenied` on S3 or Glue | No IAM on the job service account | `global.jobServiceAccount.annotations` ([values.md](references/values.md#cloud-iam-for-job-pods)). |
| Login fails after changing `initUser` | The user is created once | Log in with the first credentials. |
| `Error: INSTALLATION FAILED: ... exists and cannot be imported` | Leftovers of an earlier release (NFS RBAC, StorageClass) | Clean up as in [storage.md](references/storage.md#what-survives-uninstall), with the user's yes. |

## Next

- All values used here: [references/values.md](references/values.md).
- Storage modes and what survives: [references/storage.md](references/storage.md).
- Access and network: [references/ports.md](references/ports.md).
- Logs: [references/logs.md](references/logs.md).

## Rules

- Never delete PVCs, PVs, the NFS server, the StorageClass or the namespace without the user's
  explicit yes. They hold every job's state and the database.
- Put passwords, keys and tokens in Kubernetes Secrets referenced from values (`existingSecret`), not
  in `values.yaml` in git. Use `<PLACEHOLDER>` values in examples; never print Secret contents.
- Change the default admin password and MinIO root password before real data goes in.
- Keep the encryption key: configs saved with it cannot be read without it.
- Confirm the `kubectl` context before every install, upgrade or uninstall.
