---
name: olake-helm-deploy
description: "Deploy OLake (web UI and API, worker, Temporal, Postgres) on Kubernetes with the olake Helm chart: install it at a pinned chart and image version, reach the UI, configure it with a values file (task storage in S3 or NFS, encryption key, admin user, Ingress, external Postgres or Temporal, private registry, cloud IAM for task pods, node placement and resources for jobs, custom CA), upgrade it, read its logs and uninstall it. Use when the user wants to run OLake on EKS, GKE, AKS, kind or any Kubernetes cluster, asks about the olake Helm chart or its values, or the OLake pods do not come up. Not for docker compose (olake-ui-deploy), creating sources, destinations or jobs (olake-ui-manage), or testing OLake code changes (olake-e2e-test)."
metadata:
  olake_version: "chart olake 0.0.36, olake-ui v0.9.3, worker v0.5.1"
  status: experimental
---

# Deploy OLake on Kubernetes with Helm

The chart is `olake` from the Helm repository `https://datazip-inc.github.io/olake-helm`, built from the olake-helm repo (`helm/olake/`).
It runs `olake-ui` (UI and API), `olake-workers` (one pod per task), Temporal and Postgres, plus a store for task files: S3 or NFS.
Workloads, the flow of a task, task storage and where each kind of state lives: [../references/architecture.md](../references/architecture.md).
Every values key this skill uses, with examples: [references/values.md](references/values.md).
After the install (task pods, backup, changing the task storage, rollback): [references/operations.md](references/operations.md).
The `fusion` add-on (table maintenance) and Elasticsearch for Temporal are off by default and not covered here.

## When to use

- Install, configure, upgrade or uninstall OLake on a Kubernetes cluster with Helm.
- The OLake pods do not come up, or the UI cannot be reached.
- Not covered:
  - sources, destinations, jobs and syncs: `olake-ui-manage`, in the `olake-ui` plugin of this marketplace (`/plugin install olake-ui@olake-ai-skills`); it works the same on Kubernetes once the UI is reachable on `localhost:8000`.
  - docker compose: `olake-ui-deploy`, in the same `olake-ui` plugin.
  - why a task failed, hangs or waits (its steps, time limits, retries, the worker's failure messages): [../references/task-lifecycle.md](../references/task-lifecycle.md).
  - GitOps: planned and not written yet; the chart's guide is `helm/olake/docs/gitops.md` in the olake-helm repo.

## Inputs to collect

| Input | Default |
| --- | --- |
| Cluster | Required: the kubeconfig context to install into. Show `kubectl config current-context` and ask the user to confirm it |
| Namespace and release name | `olake` and `olake` |
| Versions | The newest chart and the newest image of olake-ui and of the worker, found in step 1 |
| Task storage | `s3` with the in-cluster MinIO for a trial; an external bucket for production. NFS only when the user asks for it or uses Fusion |
| Access to the UI | `kubectl port-forward`; Ingress or a LoadBalancer when others need it |
| Other settings | None. Each one the user wants: [references/values.md](references/values.md) |
| Folder for the values file | `~/olake-helm` |

## Prerequisites

- [ ] `helm version` shows v3.2 or later, and `kubectl version` reaches the cluster (Kubernetes 1.19 or later).
- [ ] The cluster has a default StorageClass: `kubectl get storageclass` shows one marked `(default)`, or the values set `global.storageClass`.
  Postgres, MinIO and the NFS server each claim a volume from it.
- [ ] Free capacity for the chart's requests: 2 CPU and 2 GiB of memory for the long-running pods (500m and 512Mi each for the UI, Temporal and Postgres; 250m and 256Mi each for the worker and for MinIO or the NFS server), about 0.15 CPU and 160 MiB more while the install Jobs run, plus 100m CPU and 256 MiB for each task pod running at once.
  These are requests, not usage: a task pod has no limit unless `global.jobProfiles` sets one, and a large sync uses much more memory.
  To check the numbers for other values: `helm template olake olake/olake --version <chart-version> -n olake -f ~/olake-helm/values.yaml | grep -A3 'requests:'`.
- [ ] No OLake release is there yet: `helm list -A | grep olake` prints nothing, or the user wants that release upgraded.
  The chart names its Services and Deployments `olake-ui`, `olake-workers`, `temporal` and `postgresql` whatever the release name, so a namespace holds one OLake release.
- [ ] The user may create what the mode needs: S3 mode creates only namespaced objects; NFS mode with the in-cluster NFS server also creates the cluster-wide StorageClass `nfs-server` and a ClusterRole, so it needs cluster-admin rights and runs once per cluster.
- [ ] NFS mode only: the nodes allow the `DAC_READ_SEARCH` capability; Bottlerocket nodes on EKS do not, so use S3 or an RWX StorageClass.

## Steps

Every `helm` and `kubectl` call takes `--kubeconfig ~/olake-helm/kubeconfig`, a copy of the confirmed context alone, so a change of the user's current context cannot redirect a command.
Write the flag out on every call; never keep it in a shell variable, which zsh does not split.

1. Pin the cluster: write the confirmed context to its own kubeconfig, readable only by the user, and check it reaches the cluster:

   ```bash
   mkdir -p ~/olake-helm && chmod 700 ~/olake-helm
   kubectl config view --minify --flatten --context <context> > ~/olake-helm/kubeconfig && chmod 600 ~/olake-helm/kubeconfig
   kubectl --kubeconfig ~/olake-helm/kubeconfig get nodes
   ```

2. Find the newest versions:

   ```bash
   helm show chart --repo https://datazip-inc.github.io/olake-helm olake | grep '^version'
   for repo in olake-ui olake-helm; do
     git ls-remote --tags --refs "https://github.com/datazip-inc/$repo" 'v*' | sed 's#.*refs/tags/##' \
       | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1
   done
   ```

   The first line is `<chart-version>`, then `<ui-tag>` (image `olakego/ui`) and `<worker-tag>` (image `olakego/ui-worker`).
   The chart's own image tags are `latest` with `pullPolicy: Always`, so each pod restart can bring a new release; the values file pins them.
3. Add the repository: `helm repo add olake https://datazip-inc.github.io/olake-helm && helm repo update olake`.
4. Write `~/olake-helm/values.yaml`; never edit the chart's own `values.yaml`:

   ```yaml
   olakeUI:
     image:
       tag: <ui-tag>
       pullPolicy: IfNotPresent
   olakeWorker:
     image:
       tag: <worker-tag>
       pullPolicy: IfNotPresent
   global:
     logFileStorageMode: s3
   ```

   Add each setting the user wants ([references/values.md](references/values.md)).
   Check it before installing: `helm template olake olake/olake --version <chart-version> -n olake -f ~/olake-helm/values.yaml | grep -E '^\s+image: ' | sort -u` must show `<ui-tag>` and `<worker-tag>`.
   The chart's schema does not catch a mistyped key under `olakeUI` or `olakeWorker`, which Helm then ignores: compare each key with [references/values.md](references/values.md).
5. Install in the background, and wait with the gate in the foreground:

   ```bash
   helm --kubeconfig ~/olake-helm/kubeconfig install olake olake/olake --version <chart-version> -n olake --create-namespace \
     -f ~/olake-helm/values.yaml --wait --timeout 15m > ~/olake-helm/helm-install.log 2>&1 &
   echo $! > ~/olake-helm/helm.pid
   ${CLAUDE_SKILL_DIR}/scripts/k8s-gate.sh ~/olake-helm/kubeconfig olake 600
   ```

   The gate polls every 10 seconds and stops at the first broken state: a crash loop, an image that cannot be pulled, a pod that cannot be scheduled, or a failed Job.
   It ends with `GATE PASS` and the image of each Deployment, or `GATE FAIL: <reason>` with the latest warning events.
   On a failure, stop helm (`kill "$(cat ~/olake-helm/helm.pid)"`) before fixing the cause.
6. Reach the UI:

   ```bash
   kubectl --kubeconfig ~/olake-helm/kubeconfig -n olake port-forward svc/olake-ui 8000:8000
   ```

   Open `http://localhost:8000` and log in with `admin` / `password`, or the admin user from the values.
   The port-forward stops when the UI pod restarts; start it again.

## Verify

- The gate printed `GATE PASS`, and its image lines show `<ui-tag>` and `<worker-tag>`.
- `helm --kubeconfig ~/olake-helm/kubeconfig status olake -n olake` shows `STATUS: deployed`.
- The login returns HTTP 200: `curl -s -o /dev/null -w '%{http_code}\n' -H 'Content-Type: application/json' -d '{"username":"admin","password":"password"}' http://localhost:8000/login`.

## Upgrade

1. Find the new versions (step 2), and read the chart's notes for every version in between: `helm show readme olake/olake --version <new-chart-version> | sed -n '/^## Migrating/,$p'`.
2. Set the new image tags in `values.yaml`, then upgrade without `--wait`, and run the gate:

   ```bash
   helm --kubeconfig ~/olake-helm/kubeconfig upgrade olake olake/olake --version <new-chart-version> -n olake -f ~/olake-helm/values.yaml
   ${CLAUDE_SKILL_DIR}/scripts/k8s-gate.sh ~/olake-helm/kubeconfig olake 600
   ```

   Always pass the same values file: without it, Helm resets every setting to the chart's defaults.
   The database, the task storage and their data are kept.
3. Start the port-forward again.

Never move to an older release: the OLake database may hold migrations the older server does not know.

## Logs

What each line of a task's `worker.log` means, and how far the task got: [../references/task-lifecycle.md](../references/task-lifecycle.md).

| What | Command |
| --- | --- |
| UI and API | `kubectl --kubeconfig ~/olake-helm/kubeconfig -n olake logs deploy/olake-ui -c olake-ui --since 10m \| grep -i -E 'error\|fail' \| cut -c1-250` |
| Worker | `kubectl --kubeconfig ~/olake-helm/kubeconfig -n olake logs deploy/olake-workers -c olake-workers --since 10m \| grep -i -E 'error\|fail' \| cut -c1-250` |
| A pod that does not start | `kubectl --kubeconfig ~/olake-helm/kubeconfig -n olake get events --sort-by=.lastTimestamp --field-selector type!=Normal \| tail -20` |
| One task's files, NFS mode | `kubectl --kubeconfig ~/olake-helm/kubeconfig -n olake exec deploy/olake-workers -c olake-workers -- ls -t /data/olake-jobs \| head -5`, then `logs/worker.log`, `logs/sync_<time>/olake.log`, `stats.json` in that folder |
| One task's files, S3 mode | The bucket, under `<prefix>/<task folder>/logs/`; with the in-cluster MinIO (credentials `s3LogFileStorage.minio.auth`, `olake` / `password` by default): `kubectl --kubeconfig ~/olake-helm/kubeconfig -n olake exec olake-minio-0 -- sh -c "mc alias set local http://localhost:9000 <rootUser> <rootPassword> > /dev/null && mc ls --recursive local/olake/<task folder>/"` |

The worker deletes each task pod when its task ends, so its files are the record.
A run's logs can also be read through the API: `olake-ui-manage`, section "Logs of a run".

## Uninstall

```bash
helm --kubeconfig ~/olake-helm/kubeconfig uninstall olake -n olake
```

This keeps the Postgres volume (users, sources, destinations, jobs, state), the task storage, and in NFS mode the NFS server with its StorageClass `nfs-server` and cluster roles.
A later install with the same release name and namespace finds the old data.
To remove everything, the chart's script deletes the remaining objects, the volumes and the namespace; ask first, since it deletes every job and its state:

```bash
helm pull olake/olake --version <chart-version> --untar --untardir ~/olake-helm/chart
~/olake-helm/chart/olake/uninstall.sh -n olake -r olake            # add --keep-pvcs to keep the data
```

## Common errors

For a failed, hanging or waiting task, start with the worker's own message: [../references/task-lifecycle.md](../references/task-lifecycle.md).

| Error | Cause | Fix |
| --- | --- | --- |
| Pods `Pending` with `pod has unbound immediate PersistentVolumeClaims` | No default StorageClass | Set `global.storageClass`, or mark a StorageClass as default |
| `Job.batch "olake-signup-init" is invalid: ... field is immutable` on upgrade | The Job from the last run still exists, and the new chart changes its pod template | `kubectl --kubeconfig ~/olake-helm/kubeconfig -n olake delete job olake-signup-init`, then upgrade again |
| `ErrImagePull` or `ImagePullBackOff` on a task pod | The driver image cannot be pulled: no internet access, or a private registry without credentials | Private registry settings in [references/values.md](references/values.md) |
| A sync pod `Pending` with `volume node affinity conflict` | The job's index volume is in another zone than the nodes the job may use | Align the job's node placement with that zone ([references/values.md](references/values.md), job index storage) |
| A sync fails with `OOMKilled` (exit code 137) | The task pod hit its memory limit | Raise it in `global.jobProfiles` |
| `x509: certificate signed by unknown authority` in the UI or worker log | A TLS-inspecting proxy | Custom CA in [references/values.md](references/values.md) |
| `curl: (7) Failed to connect to localhost port 8000` | The port-forward stopped, usually because the UI pod restarted | Start it again |

## Next

- Create sources, destinations and jobs: `olake-ui-manage` (plugin `olake-ui`).

## Rules

- Confirm the cluster context with the user before the first `helm` or `kubectl` call, and use only the pinned kubeconfig of step 1.
- Keep every setting in the values file, and pass that file on every `helm upgrade`.
- Set the encryption key before the first source is created, and never change it afterwards ([references/values.md](references/values.md)).
- Ask before uninstalling, before `uninstall.sh`, and before deleting a PVC: each one can delete every job and its state.
