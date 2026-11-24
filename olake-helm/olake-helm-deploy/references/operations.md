# Running OLake on Kubernetes

Tasks after the install: watch task pods, back up, change the task storage, roll back.
Read from the chart `olake-0.0.36`, the worker at olake-helm v0.5.1 (`worker/executor/kubernetes/pod.go`) and olake-ui v0.9.3 (`server/internal/utils/log_utils.go`).
Every command takes `--kubeconfig ~/olake-helm/kubeconfig` (SKILL.md step 1); `<k>` below stands for `kubectl --kubeconfig ~/olake-helm/kubeconfig -n olake`, written out in full on each call.

## Task pods

The worker creates one pod per task, and deletes it when the task ends.
Each pod carries these labels:

| Label | Value |
| --- | --- |
| `olake.io/operation-type` | `spec`, `check`, `discover`, `sync` or `clear-destination` |
| `olake.io/job-id` | The job's ID, for a sync or a clear destination |
| `olake.io/connector` | The driver, for example `postgres` |
| `olake.io/workflow-id` | The task's Temporal workflow ID, shortened to a valid label |

| What | Command |
| --- | --- |
| Tasks running now | `<k> get pods -l olake.io/operation-type -L olake.io/operation-type,olake.io/job-id,olake.io/connector` |
| A job's running sync | `<k> get pods -l olake.io/job-id=<job id>` |
| Its log while it runs | `<k> logs -f <pod>` |
| Why it does not start | `<k> describe pod <pod> \| sed -n '/^Events:/,$p'` |

After the pod is gone, its files in the task storage are the record (SKILL.md, Logs).
There is one worker pod; `olakeWorker` has no replica setting in this chart.

## Back up

All state that matters is in Postgres: users, sources, destinations, jobs, each job's sync state, and Temporal's schedules.
With the built-in Postgres, dump every database from its pod:

```bash
kubectl --kubeconfig ~/olake-helm/kubeconfig -n olake exec postgresql-0 -- pg_dumpall -U temporal > ~/olake-helm/olake-backup-$(date +%F).sql
chmod 600 ~/olake-helm/olake-backup-*.sql
```

`temporal` is `postgresql.auth.postgresUser`; the OLake database inside is `postgres`.
The dump holds the source and destination configs, encrypted only when `OLAKE_SECRET_KEY` is set.
Keep three things together: the dump, the encryption key, and `values.yaml`; without the key, the configs in the dump cannot be read.
With an external Postgres, use that database's own backups.
The task storage holds only per-run files (configs, logs, stats); losing it loses the run history, not the jobs or their state.

## Change the task storage

To leave the deprecated NFS mode for S3:

1. Set `global.logFileStorageMode: s3` and the `s3LogFileStorage` keys in `values.yaml` (references/values.md, task storage).
2. Upgrade and run the gate as in SKILL.md, Upgrade.

The jobs, their state and their schedules are in Postgres, so they carry on: the next sync continues from the saved state.
The UI and the API read run logs only from the store of the current mode, so runs before the change no longer show their logs.
Their files stay on the old volume until it is deleted: `olake-shared-storage` and, with the in-cluster NFS server, its objects (SKILL.md, Uninstall).
Every source driver must be at v0.12.0 or later before the change.

## Roll back

`helm --kubeconfig ~/olake-helm/kubeconfig -n olake history olake` lists the revisions.
`helm --kubeconfig ~/olake-helm/kubeconfig -n olake rollback olake <revision>` is safe only when the image tags of `olakeUI` and `olakeWorker` are the same in both revisions: a rollback to older images is a downgrade, and the OLake database may hold migrations the older server does not know.
After a rollback, set `values.yaml` to the values of that revision (`helm ... get values olake --revision <revision>`), or the next upgrade brings the change back.
