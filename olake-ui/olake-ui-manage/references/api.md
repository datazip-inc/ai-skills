# OLake UI API

Read from olake-ui v0.9.3: `server/routes/router.go`, `server/internal/handlers/etl/`, `server/internal/services/etl/` and `server/internal/models/dto/`.
`api-contract.md` in the olake-ui repo has the same endpoints, but its base URL, some methods and some bodies are out of date at v0.9.3; where it disagrees with this page, this page is right.

## Base URL and project

`<api>` below is `http://localhost:8000/api/v1/project/123`.
The server accepts any project id, but the UI always uses `123`, so anything created under another id does not show in the UI.
On another port or machine, change the host and port, and set `OLAKE_URL` for `api-op.py` (for example `OLAKE_URL=http://localhost:8080`).

## Login

The API uses a session cookie.

```bash
curl -s -c <work-dir>/cookies.txt -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"password"}' http://localhost:8000/login
```

Pass `-b <work-dir>/cookies.txt` on every later call.
A `401` means the session ended or the stack was recreated: log in again.

## Responses

Every response is `{"success": <bool>, "message": "<text>", "data": <object or null>}`.
On an error, `message` holds the reason; read it before anything else.

| HTTP | Meaning |
| --- | --- |
| 400 | The body failed validation, or a rule below refused it |
| 401 | Not logged in |
| 404 | The id does not exist |
| 409 | A name is taken (`check-unique`), or an operation result is asked for while it still runs |
| 500 | Anything else, including a failed operation's result |

## Asynchronous operations

Spec, test connection, discover and stream difference each run a driver container.
Their POST returns `202` with `data.operation_id` and nothing else.
Then:

- `GET <api>/operations/<operation_id>?wait=10` long-polls up to 10 seconds and returns `data.status`: `running`, `succeeded` or `failed`, with `data.error` when failed.
- `GET <api>/operations/<operation_id>/result` returns the result as `data`.

`scripts/api-op.py` does the POST, the polling and the result fetch, and saves the result to a file.

## Endpoints

| Call | Method and path | Body | Result |
| --- | --- | --- | --- |
| Driver versions | `GET <api>/sources/versions?type=<type>`, `GET <api>/destinations/versions?type=<type>` | - | `data.version`: tags, newest first |
| Spec | `POST <api>/sources/spec`, `POST <api>/destinations/spec` (async) | `{"type", "version"}` | `data.spec.jsonschema`: the config's JSON schema |
| Test source | `POST <api>/sources/test` (async) | `{"type", "version", "config"}` | `data.connection_result.status` (`SUCCEEDED` when it passed), `.message`, `.prerequisites` for CDC sources |
| Test destination | `POST <api>/destinations/test` (async) | `{"type", "version", "config", "source_type", "source_version"}` | As for a source |
| Create source or destination | `POST <api>/sources`, `POST <api>/destinations` | `{"name", "type", "version", "config"}` | The request, without the new id |
| List | `GET <api>/sources`, `GET <api>/destinations`, `GET <api>/jobs` | - | `data`: each with `id`, `name` and, for sources and destinations, the `jobs` that use it |
| Get, update, delete | `GET`, `PUT`, `DELETE <api>/sources/<id>` (also `destinations/<id>`, `jobs/<id>`) | `PUT` takes the full create body | - |
| Discover | `POST <api>/sources/streams` (async) | `{"name", "type", "version", "config", "job_id": -1, "job_name"}` | `data.available_streams` and `data.selected_streams`, or `data.streams_config` for drivers before v1.0.0 |
| Create job | `POST <api>/jobs` | See below | `data` is null |
| Stream difference | `POST <api>/jobs/<id>/stream-difference` (async) | `{"updated_available_streams_config", "updated_selected_streams_config"}` as JSON strings, or `updated_streams_config` before driver v1.0.0 | `data.difference_streams`: the streams whose tables an update clears |
| Sync now | `POST <api>/jobs/<id>/sync` | - | Starts one run |
| Runs of a job | `GET <api>/jobs/<id>/tasks` | - | `data`: `status`, `start_time`, `runtime`, `job_type` (`sync` or `clear`) and `file_path`, per run |
| Run logs | `POST <api>/jobs/<id>/tasks/1/logs?source=<all, sync or worker>&limit=<n>&direction=older&cursor=<c>` | `{"file_path": "<file_path of the run>"}` | `data.logs`, and cursors to page through them |
| Download run logs | `GET <api>/jobs/<id>/logs/download?file_path=<file_path>` | - | A `.tar.gz` |
| Cancel the running sync | `GET <api>/jobs/<id>/cancel` | - | - |
| Pause or resume the schedule | `POST <api>/jobs/<id>/activate` | `{"activate": false}` or `true` | - |
| Clear destination | `POST <api>/jobs/<id>/clear-destination` | - | Starts a run that drops the job's tables and resets its state |
| Clear destination still running? | `GET <api>/jobs/<id>/clear-destination` | - | `data.running` |
| Is a name free? | `POST <api>/check-unique` | `{"name", "entity_type": "job", "source" or "destination"}` | `data.unique` |

Supported `type` values at v0.9.3: sources `mysql`, `postgres`, `oracle`, `mongodb`, `kafka`, `s3` (and others listed in `SupportedSourceTypes` in `server/internal/constants/constants.go`), destinations `iceberg` and `parquet`.

## Create a job

```json
{
  "name": "pg_orders",
  "frequency": "0 * * * *",
  "activate": true,
  "source": {"id": 1},
  "destination": {"id": 2},
  "available_streams_config": "<data.available_streams from discover, as a JSON string>",
  "selected_streams_config": "<data.selected_streams, edited, as a JSON string>"
}
```

- `source` and `destination` with an `id` reuse that entity unchanged.
  Without an `id`, they need `name`, `type`, `version` and `config`, and the server creates a new one with that name.
- The two streams fields are JSON strings, not objects.
  A driver before v1.0.0 returns `streams_config` instead; send that alone, also as a string.
- `frequency` is a five-field cron in UTC, and is required.
- `activate` defaults to `true`: the schedule starts at once.
  A paused job (`activate: false`) also refuses a manual sync, so for a job that runs only on demand, give it a cron that rarely fires, such as `0 0 1 1 *`.
- The response holds no id: list the jobs and match the name.

`selected_streams` is grouped by namespace, one entry per stream:

```json
{"public": [{"stream_name": "orders", "sync_mode": "cdc", "normalization": true}]}
```

Keep only the streams to sync, and set `sync_mode` on each to one of `full_refresh`, `incremental`, `cdc` or `strict_cdc`, among those the stream's entry in `available_streams` lists as supported.

## Rules the server enforces

| Rule | Error |
| --- | --- |
| Names of jobs, sources and destinations are unique within the project | `job name '<name>' is not unique`, `source name '<name>' is not unique` |
| A source or destination used by a job cannot be deleted | `cannot delete source '<name>' id[<id>] because it is used in <n> jobs; please delete the associated jobs first` |
| A paused job does not sync | `job is paused, please unpause to run sync` |
| The split streams format needs a source driver at v1.0.0 or later | `source version <v> does not support the split streams format (minimum v1.0.0)` |
| Updating a job cancels its running sync, and is refused while a clear destination runs | - |

## Runs and their files

A run's `file_path` is its Temporal workflow ID, `sync-123-<job id>-<start time>`.
`status` is Temporal's: `Running`, then `Completed`, `Failed`, `Canceled`, `Terminated` or `TimedOut`.
The run's files (configs, `state.json`, `stats.json`, logs) are in the job folder named after the SHA-256 of that workflow ID: [../../references/architecture.md](../../references/architecture.md).
