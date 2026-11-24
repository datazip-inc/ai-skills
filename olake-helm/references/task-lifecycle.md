# How the worker runs a task

Shared by every skill in this plugin, and the reference for why a task failed, hangs or waits.
Read from the worker at olake-helm v0.5.1 (`worker/temporal/workflow.go`, `activity.go`, `worker/executor/`, `worker/utils/failure/failure.go`) and olake-ui v0.9.3 (`server/internal/services/temporal/utils.go`).
The same worker runs both stacks: on docker compose each task is a container on the host's Docker, on Kubernetes a pod.

## Steps of a task

Each line is a line the worker writes to the task's `logs/worker.log`, in order, so the last one present shows how far the task got.

| Step | What happens | Line in `worker.log` |
| --- | --- | --- |
| 1. Pick up | A worker takes the task from Temporal | Sync: `Worker <id> picked up job <name> (id <n>), attempt <k>` |
| 2. Load the job | Reads the job from the OLake database, decrypts its configs with `OLAKE_SECRET_KEY`, writes them into the task folder | A failure here ends the sync at once: `failed to get job data: ...` |
| 3. Check the driver | S3 mode refuses a driver before v0.12.0 | `connector version <v> does not support S3 storage mode: requires v0.12.0 or later` |
| 4. Start the driver | Compose: pulls the image only when it is missing locally, within 2 minutes, then starts the container. Kubernetes: creates the pod, which pulls the image | `Pulling image <image>`, `image pull timed out`; `Pod <pod> scheduled on node <node>, <resources>`, `pod is waiting to be scheduled` |
| 5. Run | The driver writes its own log to `logs/sync_<time>/olake.log` (`connector-*.log` chunks in S3 mode); the worker sends a heartbeat to Temporal about every 24 seconds | Kubernetes: `Pod <pod> completed successfully` at the end |
| 6. Clean up | Always, also after a failure or a cancel: removes the container or pod, then saves `state.json` into the job's record | `successfully cleaned up and persisted state` |
| 7. Alert | A failed sync, not a cancelled one, posts to the project's webhook (`webhook_alert_url` in the project settings) when one is set | - |

## Time limits

| Task | Limit | Set by |
| --- | --- | --- |
| Spec | 5 minutes | olake-ui |
| Test connection, discover | 10 minutes | olake-ui |
| Sync, clear destination | 30 days | olake-ui and the worker |
| Clean up after a sync | 15 minutes | Worker |
| Heartbeat | Missing for 30 seconds means the worker is gone | Worker |
| A pod that cannot be scheduled | Fails after 10 minutes of a lasting scheduling failure | Worker, Kubernetes only |

A sync that runs long is not stuck as long as `olake.log` keeps growing; a sync has no limit that ends it before 30 days.

## Retries

- Spec, test connection and discover run once; a failure is final.
- A sync is retried only when the worker itself is lost: the worker pod or container restarts, or its heartbeat stops for 30 seconds.
  Temporal then gives the task to a worker again, after 5 seconds, doubling up to 5 minutes, without a limit on attempts; `worker.log` shows `attempt 2` and up.
  The new attempt adopts the driver that is still running (`adopting running container` on compose, `pod already exists, resuming polling` on Kubernetes) instead of starting a second one.
- Every failure of the sync itself is final, with no retry: the driver exited non-zero, it ran out of memory, its pod was evicted or could not be scheduled, the job could not be read, or the driver version does not fit the storage mode.
  The next attempt is the next scheduled run or a manual sync, and it starts from the state saved at step 6.
- A clear destination is different: any failure of its driver is retried, after 5 seconds, doubling up to 5 minutes, without a limit, and the job's schedule stays paused all that time.
  `jobs/<id>/cancel` does not stop it, because it cancels only syncs.
  To stop it and resume the schedule, olake-ui has an internal call: `curl -s -X POST http://localhost:8000/internal/project/123/jobs/<job id>/clear-destination/recover`.
- The driver's own retries, for a source call that fails, are separate: the source's `retry_count` (0 means the default 3, with waits of 60, 120 and 240 seconds).

## Why a sync failed: the worker's message

On a failed sync, the worker writes one explanation to `worker.log`: a headline, details, and sometimes a recommendation.

| Headline starts with | Cause | Fix |
| --- | --- | --- |
| `Sync failed due to insufficient memory.` | The driver was OOMKilled, killed with exit code 137, its pod vanished while it ran, or the driver logged `runtime: out of memory` or `java.lang.OutOfMemoryError` | More memory: `global.jobProfiles` on Kubernetes, Docker's memory on compose. The details line names the memory limit |
| `Sync failed because Kubernetes evicted the sync pod` | Node pressure, or the pod passed a resource limit | More memory, or nodes with more room |
| `Sync failed: connector exited with code <n>. See Sync logs for the error.` | The driver failed on its own: a source or destination error | Read the last `ERROR` or `FATAL` line of `olake.log`; then the driver or destination skill of the `olake-go` plugin |
| `Sync failed: pod <pod> did not run to completion (reason: Unschedulable)` | No node fitted the pod for 10 minutes: resources, `nodeSelector`, taints, or an index volume in another zone | Fix the job's profile, or add capacity |
| `Sync failed: <error>`, with no other explanation | The driver never started, for example the container could not be created | The error names it |

## Waits that never fail on their own

- **Kubernetes, image pull:** a task pod in `ErrImagePull` or `ImagePullBackOff` stays `Pending`, and the worker keeps waiting with no line in `worker.log`, until the task's limit: 10 minutes for a test or discover, 30 days for a sync.
  Look at the pod (`kubectl get pods -l olake.io/job-id=<job id>`, then its events), fix the image name, registry or credentials, and cancel the sync.
- **A scheduling failure that is not lasting** (the cluster autoscaler adding a node, a volume still detaching from another node) does not start the 10-minute count.
