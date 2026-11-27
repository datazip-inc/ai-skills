# Logs (Helm)

Add `-n olake` (or the release namespace) to every command.

## OLake components

```bash
kubectl get pods -n olake
kubectl logs -n olake deploy/olake-workers --tail=200 -f
kubectl logs -n olake deploy/olake-ui --tail=200
kubectl logs -n olake deploy/temporal --tail=200
kubectl logs -n olake job/olake-signup-init
kubectl describe pod -n olake <POD>       # events: scheduling, image pulls, OOMKilled
```

`olake-workers` logs each job pod it creates and the pod's final status. Its log level is
`olakeWorker.config.logging.level` (default `info`).

## Job pods

The worker deletes a job pod when the run ends, so `kubectl logs` works only while it runs:

```bash
kubectl get pods -n olake -l app.kubernetes.io/managed-by=olake-workers
kubectl get pods -n olake -l olake.io/job-id=<JOB_ID>,olake.io/operation-type=sync
kubectl logs -n olake -f <POD>
```

Labels on job pods: `olake.io/job-id`, `olake.io/operation-type` (`check`, `discover`, `sync`,
`clear-destination`), `olake.io/connector`, `olake.io/workflow-id`. After the run, read the log file
on shared storage, or the job's run page in the UI.

## Run folders

One folder per run on shared storage:

| Run | Folder name |
| --- | --- |
| Test connection, discover | The Temporal workflow ID. |
| Sync, clear destination | `sha256` hex of the workflow ID `sync-<projectID>-<jobID>` (project ID `123`). |

```bash
printf '%s' "sync-123-<JOB_ID>" | shasum -a 256 | cut -d' ' -f1
```

The sync log is `<run folder>/logs/sync_<timestamp>/olake.log`.

| Mode | Read it with |
| --- | --- |
| NFS | `kubectl exec -n olake deploy/olake-workers -- ls -t /data/olake-jobs/<RUN_FOLDER>/logs/`, then `cat` the file. |
| S3 | `aws s3 ls s3://<BUCKET>/<PREFIX>/<RUN_FOLDER>/logs/ --recursive` (add `--endpoint-url` for MinIO or GCS). Logs are uploaded in chunks while the run goes. |

The run folder also holds `source.json` and `destination.json` with credentials: never print them;
read only the fields needed.

Find the first `ERROR` or `FATAL` line, then match it in the driver or destination skill.

## Temporal

With `temporal.ui.enabled: true`:
`kubectl port-forward -n olake svc/temporal-ui 8081:8081`, then `http://localhost:8081`. Each job is
workflow `sync-<projectID>-<jobID>`; it shows retries and the activity error. Use it when a job stays
running or queued and no job pod exists.
