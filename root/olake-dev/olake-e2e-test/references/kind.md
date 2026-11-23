# Environment: Kubernetes with kind

The OLake stack (UI, worker, Temporal, Postgres, and shared storage for job files) runs in a kind cluster, installed from the olake-helm chart with a values overlay in the run directory.
The worker starts one pod per task (spec, check, discover, sync).
The driver runs in a pod, but the test source and destination it connects to do not: they stay as Docker containers on the host, started as in the test data reference.
Pods reach them through `host.docker.internal` on Docker Desktop.
The UI service is port-forwarded to `localhost:8000`, so the API calls are the same as on docker compose.

## Contents

- Isolation: one cluster and one kubeconfig per stack
- 1. Cluster
- 2. Load images
- 3. Values overlay
- 4. Install, gate and port-forward
- 5. Logs: workflow directories in `/data/olake-jobs` (NFS mode) or the in-cluster MinIO (S3 mode)
- 6. Change an image on a running stack
- 7. Handoff rows
- 8. Teardown

## Isolation: one cluster and one kubeconfig per stack

The user's kubeconfig can hold real clusters, and its current context can be one of them.
So each stack has its own cluster, `olake-dev-<run-id>`, and its own kubeconfig, `<run-dir>/kubeconfig`.
Pass `--kubeconfig <run-dir>/kubeconfig` on every `kubectl` and `helm` call, never rely on the current context, and never write to `~/.kube/config`.
Never put the flag in a shell variable: zsh does not split it, and the command fails or falls back to the user's context.

## 1. Cluster

Preflight: `kind get clusters` lists clusters the user already has; never delete one that is not this stack's.

```bash
kind create cluster --name olake-dev-<run-id> --kubeconfig <run-dir>/kubeconfig --wait 180s
kubectl --kubeconfig <run-dir>/kubeconfig get nodes
```

The node runs as the Docker container `olake-dev-<run-id>-control-plane`. Record the cluster name and the kubeconfig path in `stack.md`.

## 2. Load images

Load every image the stack runs from a local build or a pinned tag: the UI, the worker, and every driver image the tests use, including `olakego/source-mysql` for the destination spec.

```bash
docker save --platform linux/<arch> -o <run-dir>/images/<name>.tar <image>:<tag>
kind load image-archive <run-dir>/images/<name>.tar --name olake-dev-<run-id>
```

`<arch>` is the node's architecture: `docker exec olake-dev-<run-id>-control-plane uname -m` (`aarch64` is `arm64`, `x86_64` is `amd64`).
Do not use `kind load docker-image` for pulled images: with Docker Desktop's image store it imports every platform, and fails with `ctr: content digest sha256:...: not found` for the platforms that were never pulled.
Check: `docker exec olake-dev-<run-id>-control-plane crictl images | grep olakego` lists every image with its tag.

Job pods set no pull policy, so Kubernetes uses `IfNotPresent` for any tag except `latest`, and a loaded driver image is used as it is.

## 3. Values overlay

Write `<run-dir>/values.yaml`; never edit the chart's own `values.yaml`.

```yaml
olakeUI:
  image:
    repository: olakego/ui
    tag: <tag>
    pullPolicy: IfNotPresent    # the chart default is Always, which fails for a loaded image
  env:
    TELEMETRY_DISABLED: "true"
    APP_ENV: development        # with the next line: only when a driver was built
    CUSTOM_DRIVER_VERSION: <driver tag>
olakeWorker:
  image:
    repository: olakego/ui-worker
    tag: <tag>
    pullPolicy: IfNotPresent
  env:
    TELEMETRY_DISABLED: "true"
```

- `<tag>` is the run tag when the stack built that image, otherwise the pinned release tag recorded in `stack.md`.
- Job files use the chart default, NFS (`global.logFileStorageMode: nfs`, deprecated for the end of 2026, but what ships today). Set `global.logFileStorageMode: s3` when the test is about S3 log storage or the change touches it.
- Add only what the test needs on top, for example `gitops.enabled: true` for GitOps.
- Check the overlay before installing: `helm template olake <olake-helm>/helm/olake -n olake -f <run-dir>/values.yaml | grep -E '^\s+image: ' | sort -u` shows the intended tags.

## 4. Install, gate and port-forward

The chart comes from `<olake-helm>/helm/olake`; it has no dependencies to build.
When olake-helm is not part of the change, use the managed clone at the pinned release tag of `olakego/ui-worker`.

```bash
helm --kubeconfig <run-dir>/kubeconfig install olake <olake-helm>/helm/olake -n olake --create-namespace -f <run-dir>/values.yaml --wait --timeout 15m > <run-dir>/logs/helm-install.log 2>&1
```

Run it in the background; a first install takes about 2 minutes with the images already on the machine.
`--wait` can return before the `olake-signup-init` job has finished, so the gate also waits for jobs:

```bash
kubectl --kubeconfig <run-dir>/kubeconfig -n olake wait --for=condition=Available deploy --all --timeout=300s
kubectl --kubeconfig <run-dir>/kubeconfig -n olake wait --for=condition=Complete job --all --timeout=300s
kubectl --kubeconfig <run-dir>/kubeconfig -n olake get deploy -o wide
```

The last command shows the image of each deployment: the run tag for each built image, the pinned release tag for the others.

Port-forward the UI in the background, then log in; a 200 is the end of the gate:

```bash
nohup kubectl --kubeconfig <run-dir>/kubeconfig -n olake port-forward svc/olake-ui 8000:8000 > <run-dir>/logs/port-forward.log 2>&1 &
echo $! > <run-dir>/port-forward.pid
curl -s -o /dev/null -w '%{http_code}\n' -c <run-dir>/cookies.txt -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"password"}' http://localhost:8000/login
```

The port-forward stops when the UI pod restarts (an upgrade, a crash): start it again, and check `<run-dir>/logs/port-forward.log` when a call cannot connect.

## 5. Logs

Every task writes its files to a workflow directory with the same name as on docker compose: the workflow ID for spec, test connection and discover, and the SHA-256 of `sync-<project>-<job id>-<start time>` for a sync.
The worker deletes each task pod when it ends, so read these files, not `kubectl logs` of the pod.
Where they are depends on `global.logFileStorageMode`:

| Mode | Where the files are | Layout |
| --- | --- | --- |
| `nfs` (the chart default) | `/data/olake-jobs/<workflow-dir>/` on the shared volume, in the worker pod (`/tmp/olake-config` in the UI pod is the same volume) | As on docker compose: `logs/worker.log`, `logs/sync_<time>/olake.log`, `stats.json`, `state.json` |
| `s3` | The bucket `olake` in the in-cluster MinIO; `/data/olake-jobs` stays empty | Logs in chunks: `logs/worker/worker-*.log`, `logs/sync_<time>/connector-*.log` |

In `nfs` mode, `<w>` below stands for `kubectl --kubeconfig <run-dir>/kubeconfig -n olake exec deploy/olake-workers -c olake-workers --`:

| What | Command |
| --- | --- |
| Which workflow directory a job's syncs used (one per sync run) | `<w> sh -c "grep -l 'picked up job <job name> ' /data/olake-jobs/*/logs/worker.log"` |
| Newest workflow directories (spec, test, discover are named after their workflow ID) | `<w> ls -t /data/olake-jobs \| head -5` |
| Which image a task ran | `<w> grep -h 'Starting pod' /data/olake-jobs/<workflow-dir>/logs/worker.log \| cut -c1-250` |
| Rows a sync wrote (`Synced Records`; a progress file, not the status, which comes from the job tasks API) | `<w> cat /data/olake-jobs/<workflow-dir>/stats.json` |
| One task, from the worker | `<w> grep -h -E '"level":"(error\|warn)"\|Starting pod' /data/olake-jobs/<workflow-dir>/logs/worker.log \| cut -c1-250` |
| Sync log | `<w> sh -c "grep -h -i -E 'error\|fatal\|creating table\|successfully wrote' /data/olake-jobs/<workflow-dir>/logs/*/olake.log" \| cut -c1-250` |
| Worker, across tasks | `kubectl --kubeconfig <run-dir>/kubeconfig -n olake logs deploy/olake-workers -c olake-workers --since 10m \| grep -i -E 'error\|fail' \| cut -c1-250` |
| UI and API | `kubectl --kubeconfig <run-dir>/kubeconfig -n olake logs deploy/olake-ui -c olake-ui --since 10m \| grep -i -E 'error\|fail' \| cut -c1-250` |
| A pod that does not start | `kubectl --kubeconfig <run-dir>/kubeconfig -n olake get events --sort-by=.lastTimestamp --field-selector type!=Normal \| tail -20` |

`<w>` is shorthand for this table only: write the command out in full each time, never as a shell variable.

In `s3` mode, read the bucket with `mc` inside the MinIO pod (`olake` / `password` are the chart's default MinIO credentials, `s3LogFileStorage.minio.auth`):

```bash
kubectl --kubeconfig <run-dir>/kubeconfig -n olake exec olake-minio-0 -- sh -c "mc alias set local http://localhost:9000 olake password > /dev/null && mc ls --recursive local/olake/<workflow-dir>/"
kubectl --kubeconfig <run-dir>/kubeconfig -n olake exec olake-minio-0 -- sh -c "mc alias set local http://localhost:9000 olake password > /dev/null && mc find local/olake/<workflow-dir>/logs --name 'connector-*' --exec 'mc cat {}'" | grep -i -E 'error|fatal|successfully wrote' | cut -c1-250
```

For the worker log of one task, use `--name 'worker-*'` instead.

## 6. Change an image on a running stack

Build the image with its new run tag, load it as in section 2, set the new tag in `<run-dir>/values.yaml`, and upgrade:

```bash
helm --kubeconfig <run-dir>/kubeconfig upgrade olake <olake-helm>/helm/olake -n olake -f <run-dir>/values.yaml --wait --timeout 10m
```

Only the deployments whose values changed are rolled; the database and MinIO keep their data.
Then start the port-forward again (section 4).

## 7. Handoff rows

| What | Value |
| --- | --- |
| OLake UI | `http://localhost:8000` while the port-forward runs, login `admin` / `password` |
| API | `http://localhost:8000/api/v1/project/123`, cookie login with `POST /login` |
| Port-forward | PID in `<run-dir>/port-forward.pid`; start it again with the command in section 4 |
| kubectl | `kubectl --kubeconfig <run-dir>/kubeconfig -n olake ...` |
| Temporal UI | Set `temporal.ui.enabled: true` in the overlay, then `kubectl --kubeconfig <run-dir>/kubeconfig -n olake port-forward svc/temporal-ui 8081:8081` |
| Driver version to pick in the UI | The run tag, when a driver was built; else the pinned release tag |
| Image tags in use | One line per image |
| Logs | Section 5 |

## 8. Teardown

```bash
kill "$(cat <run-dir>/port-forward.pid)"
kind delete cluster --name olake-dev-<run-id> --kubeconfig <run-dir>/kubeconfig
```

Deleting the cluster removes everything the chart created. The loaded images stay in the host's Docker; remove `<run-dir>/images/` and the images only when the user asks.
