---
name: olake-ui-manage
description: "Use a running OLake UI stack: create and test sources and destinations, discover streams, create a job with chosen streams and sync modes, run a sync, follow its status and logs, and change, pause, cancel, clear or delete jobs, in the web UI or through its REST API. Use when the user wants to connect a database to OLake UI, set up or run a replication job, check why a test connection, discover or sync failed in OLake UI, read a job's run logs, or script OLake UI through its API. Not for installing or upgrading the stack (olake-ui-deploy), Kubernetes deployment, GitOps manifests, or testing OLake code changes (olake-e2e-test)."
metadata:
  olake_version: "olake-ui v0.9.3, worker v0.5.1, drivers v1.2.2"
  status: experimental
---

# Use OLake UI: sources, destinations, jobs and syncs

The stack must already be running and reachable: `olake-ui-deploy` (this plugin) sets it up with docker compose; for Kubernetes, `olake-helm-deploy` is planned and not written yet.
Every call, body and server rule is in [references/api.md](references/api.md).
What each change does to running syncs, sync state, the schedule and the destination tables is in [references/behaviours.md](references/behaviours.md): read it before changing or deleting anything that has synced.
How a task flows from the API to the driver, and where its files land: [../references/architecture.md](../references/architecture.md).

## When to use

- Create, test, change or delete a source or a destination.
- Discover streams, create a job, choose streams and sync modes, run a sync, read its logs.
- A test connection, discover or sync fails in OLake UI.
- Not covered: what a source's or destination's config keys mean, which sync mode to pick, and driver or writer errors.
  Those are in the `olake-go` plugin of this marketplace (`/plugin install olake-go@olake-ai-skills`): `olake-driver-postgres` and the other `olake-driver-*` skills, `olake-destination-iceberg`, and `olake-troubleshoot` for a failing sync.
  Without that plugin, use the `title` and `description` of each key in the spec's JSON schema (step 3), and do not guess a key's meaning beyond them.

## Inputs to collect

Ask only for what is missing, and never echo a password or key back.

| Input | Default |
| --- | --- |
| UI or API | The API when the agent does the work; the UI when the user wants to click through it |
| OLake URL and login | `http://localhost:8000`, `admin` / `password` |
| Source type and connection | Required |
| Destination type and its catalog and storage | Required |
| Streams and sync mode for each | Every discovered stream, with the mode the user names |
| Schedule | On demand only (`0 0 1 1 *`, started with sync now) |
| Driver versions | The newest the stack lists (step 2) |
| Work folder for request and result files | `~/olake/api` |

## In the UI

| Task | Where |
| --- | --- |
| Create or test a source | Sources, then Create Source (`/sources/new`) |
| Create or test a destination | Destinations, then Create Destination (`/destinations/new`) |
| Create a job, choose streams and sync modes | Jobs, then Create Job (`/jobs/new`) |
| Sync now, pause, edit, clear destination, delete | The job's menu in Jobs; settings at `/jobs/<id>/settings` |
| Runs and their logs | `/jobs/<id>/history`, then a run's logs |

The UI calls the same API, so the rules and errors in [references/api.md](references/api.md) apply to both.

## Steps, through the API

1. Make the work folder private, since request bodies hold credentials, and log in:

   ```bash
   mkdir -p ~/olake/api && chmod 700 ~/olake/api && cd ~/olake/api
   curl -s -c cookies.txt -H 'Content-Type: application/json' \
     -d '{"username":"admin","password":"password"}' http://localhost:8000/login
   ```

   `<api>` below is `http://localhost:8000/api/v1/project/123`; pass `-b cookies.txt` on every `curl`.
2. Pick the driver versions: `curl -s -b cookies.txt '<api>/sources/versions?type=<source-type>'`, and the same under `destinations`.
   The list is newest first; use the newest unless the user names one.
3. Get each spec, and build each config from its schema:

   ```bash
   python3 -I ${CLAUDE_SKILL_DIR}/scripts/api-op.py . sources/spec spec-src-body.json spec-src.json
   ```

   with `spec-src-body.json` holding `{"type": "<source-type>", "version": "<version>"}`.
   Read `data.spec.jsonschema` in the result, and use only keys it defines.
   An Iceberg destination keeps each catalog's keys under `properties.writer.dependencies.catalog_type.oneOf`.
4. Test the source, then the destination, with the same script (`sources/test`, `destinations/test`); the bodies are in [references/api.md](references/api.md).
   A test passed only when `data.connection_result.status` is `SUCCEEDED`; otherwise `data.connection_result.message` says why.
   For a CDC source, also read `data.connection_result.prerequisites`: a `required` check that did not pass stops CDC.
5. Create the source and the destination (`POST <api>/sources`, `POST <api>/destinations`), then list them to read their ids.
6. Discover (`sources/streams`) with `job_id` `-1` and the job's name as `job_name`.
   Check that every stream the user wants is in `data.available_streams`.
7. Build `selected_streams` from the discover result: keep the streams to sync, and set `sync_mode` on each explicitly (the discover default can differ from what the user wants).
   Drivers from v1.0.0 return the split format (`available_streams`, `selected_streams`); use it. Only an older driver returns `streams_config` (behaviours: streams catalog formats).
8. Create the job (`POST <api>/jobs`) with the source and destination ids and both streams catalogs as JSON strings, then list the jobs to read its id.
9. Note the `file_path` values `GET <api>/jobs/<id>/tasks` already lists, then start a sync: `curl -s -b cookies.txt -X POST <api>/jobs/<id>/sync`.
   The call succeeds but starts nothing while a run of the job is still running.
10. Follow it: poll the tasks every 15 seconds until a run with a new `file_path` appears, then read only that run.
    Stop at its first status other than `Running`, or when its logs (next section) show no new line for 2 minutes, and report which.

## Verify

- Both tests returned `SUCCEEDED`.
- The run's status is `Completed`.
- `stats.json` in the run's folder shows the synced rows; on compose it is `olake-data/<sha256 of the run's file_path>/stats.json` in the stack's folder.
- The rows are in the destination: query it with the destination's tools.

## Logs of a run

```bash
curl -s -b cookies.txt -H 'Content-Type: application/json' -d '{"file_path":"<file_path of the run>"}' \
  '<api>/jobs/<id>/tasks/1/logs?source=all&limit=200' > logs.json
```

`source=sync` gives the driver's log, `source=worker` the worker's, `all` both by time.
With no cursor the call returns the newest lines; pass `cursor=<older_cursor>` from the response to page back.
For the whole log, download it: `GET <api>/jobs/<id>/logs/download?file_path=<file_path>`.
Look first for lines with `error` or `fatal`, then name the failing stage: test connection, discover, or sync.
For a test or a discover, the failure is in the operation's `data.error` and in its job folder (`<operation_id>/logs/worker.log`).

## Change a job

Each change below can cancel a running sync or clear tables: [references/behaviours.md](references/behaviours.md) says which.

| Task | Call | Note |
| --- | --- | --- |
| Change streams, schedule or settings | `PUT <api>/jobs/<id>` with the full create body | Cancels a running sync first. To clear the tables of streams whose settings changed, first run `jobs/<id>/stream-difference` with the new catalogs, and send its `data.difference_streams` as `difference_streams` (a JSON string) in the `PUT` |
| Pause or resume the schedule | `POST <api>/jobs/<id>/activate` | A paused job also refuses sync now |
| Cancel the running sync | `GET <api>/jobs/<id>/cancel` | |
| Clear destination | `POST <api>/jobs/<id>/clear-destination` | Drops the job's tables and resets its state; the next sync starts from a full load |
| Delete | `DELETE <api>/jobs/<id>` | Delete the jobs before their source or destination |

## Common errors

| Error | Cause | Fix |
| --- | --- | --- |
| HTTP `401` | The session ended, or the stack was recreated | Log in again |
| Created items do not show in the UI | They were made under a project id other than `123` | Use `123` |
| `job is paused, please unpause to run sync` | The job is inactive | Resume it, or keep it active with a rarely firing cron |
| `source version <v> does not support the split streams format` | The source driver is older than v1.0.0 | Send `streams_config` from discover instead, or use a newer driver |
| `... is not unique` | The name is taken in the project | Pick another name, or reuse the existing one by its id |
| `cannot delete source ... used in <n> jobs` | Jobs still use it | Delete those jobs first |

## Rules

- Set `sync_mode` on every selected stream; never rely on the default.
- Keep request bodies, which hold credentials, in the private work folder, and never print them.
- Ask before clear destination, deleting a job, or changing streams of a job that has synced: each drops synced data or state.
- Ask before updating a source or destination while a job that uses it is syncing: the update cancels that sync.
