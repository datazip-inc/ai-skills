# How OLake UI behaves when things change


## Streams catalog formats

| Format | Fields | Driver versions |
| --- | --- | --- |
| Split (v2) | `available_streams` and `selected_streams` | v1.0.0 or later |
| Legacy (v1) | `streams_config` | Before v1.0.0 |

Discover returns the format the driver writes, and a job is created in that format.
Use the split format: every current driver writes it.
A job never moves from split back to legacy.
Upgrading a source to v1.0.0 or later converts its legacy jobs to split in the same update; if one job fails to convert, the whole update is refused.
Downgrading a source below v1.0.0 is refused while a split job uses it.
On a stack started with `CUSTOM_DRIVER_VERSION` (a development build), the server treats every driver version as v1.0.0 or later.

## What cancels a running sync

| Action | Syncs it cancels |
| --- | --- |
| Update a source | Every job that uses the source |
| Update a destination | Every job that uses the destination |
| Update a job | That job |
| Cancel (`jobs/<id>/cancel`) | That job |

Creating a source, destination or job cancels nothing.
Deleting a job removes its schedule and its record, but does not stop a run in progress and does not drop its destination tables: cancel the run first.

## Sync now and the schedule

- A job has one schedule, `schedule-sync-123-<job id>`, created with the job and paused while the job is inactive.
- Sync now, and every scheduled start, is skipped while a run of the same job is still running: the call returns success, but no new run appears.
  Before reporting a sync as started, check that `jobs/<id>/tasks` lists a new `file_path`.
- A paused job refuses sync now: `job is paused, please unpause to run sync`.
- Pause and resume with `jobs/<id>/activate`, which pauses and resumes the schedule.
- Changing `frequency` in a job update changes the schedule.

## Sync state

- The driver writes its progress (cursors, finished chunks, CDC position) to `state.json` in the run's folder.
- When the run ends, whether it completed, failed or was canceled, the worker saves that `state.json` into the job's record in the OLake database.
- The next run starts from the saved state; with an empty state (`{}`) it starts with a full load.
- Editing a job, its source or its destination does not reset the state; only clear destination does.

## Changing streams clears their tables

When a job update changes the streams:

1. The UI runs stream difference (`jobs/<id>/stream-difference`) on the old and new catalogs.
   The driver decides which streams differ; the server does not.
2. If any differ, the UI warns "Modifying stream configurations will clear destination data for the impacted streams", and sends the result as `difference_streams` in the update.
3. The server cancels the running sync, waits up to 30 seconds for it to stop, pauses the schedule, and runs clear destination for those streams only.
4. The worker resumes the schedule when the clear completes.

An API client that sends no `difference_streams` gets no clear, and the tables keep the data written under the old settings.
Stream difference needs the source driver at v0.3.0 or later.
While a clear runs, a job update is refused: `clear-destination is in progress, cannot update job`.

## Clear destination, started by hand

- Refused for a paused job, and while a sync runs: `sync is in progress, please wait or cancel the sync`. Cancel the sync first.
- It pauses the schedule, resets the job's state to `{}`, and clears the destination for all of the job's streams.
- The worker resumes the schedule when the clear completes, and the next sync is a full load.
- It needs the source driver at v0.3.0 or later.

## Advanced settings

A job's `advanced_settings`, shown in the UI as Advanced Settings in the job's settings:

| Key | UI label | Effect |
| --- | --- | --- |
| `max_discover_threads` | Max Discover Threads | Parallel threads for discover; driver v0.3.18 or later. Send it in the discover body too |
| `target_query_engines` | Target Query Engines | The engines that will query the tables; each stream's `available_update_types` comes from them. OLake stores them only here, so send them in every discover body, and discover again after changing them. Needs driver v0.11.0 or later |
| `index_required` | (none: the UI sets it) | `true` when any selected stream upserts with positional deletes. Set it the same way from the API |

The UI recommends clear destination when Snowflake is among the target query engines: Snowflake can read stale data from old Iceberg snapshots.

## Source config rules

- Postgres with CDC: `update_method.preserve_toast_values` can only be set when the source is created.
  An update that changes it is refused: `preserve_toast_values can only be set when the source is created`.
- Names are unique per kind within the project, so a source and a destination may share a name, but two sources may not.
