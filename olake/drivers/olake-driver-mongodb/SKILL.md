---
name: olake-driver-mongodb
description: "Connect MongoDB (self-hosted replica set, sharded cluster, Atlas, DocumentDB-compatible hosts) to OLake as a source (mirrors drivers/mongodb): source.json, read role, SRV and replica set options, and CDC through change streams. Use when the source is MongoDB and the user wants to run a sync."
metadata:
  parent: olake-driver-abstract
  status: experimental
---

# MongoDB source

Image: `olakego/source-mongodb:<tag>`. Sync modes: `full_refresh`, `incremental`, `cdc`, `strict_cdc`.
The run (`check`, `discover`, `sync`) is in `olake-protocol`.

## When to use

- The source is MongoDB: replica set, sharded cluster, Atlas.
- `check` fails on a MongoDB host, or reports that change streams are not available.

## Inputs to collect

Ask only for what is missing. Never echo a password or key back.

| Input | Example | Where it comes from |
| --- | --- | --- |
| `hosts` | `["mongo-1:27017", "mongo-2:27017"]` | User. A list. From a container, `localhost` is the container: use `host.docker.internal` or the Docker network service name. |
| `database` | `shop` | User. One database per source. |
| `username`, `password`, `authdb` | `olake_user`, `<PASSWORD>`, `admin` | User or DBA |
| Atlas or SRV record? | yes / no | User. Yes: `"srv": true` and one host without a port. |
| `replica_set` | `rs0` | User, when connecting to a replica set by host list. |
| Changes needed: deletes, near real time? | yes / no | User. Yes: CDC. |

## Prerequisites

- [ ] Every mode: the user has the `read` role on the database (it includes `find` and
      `changeStream`).
- [ ] CDC only: the deployment is a replica set or sharded cluster. A standalone `mongod` has no
      change streams; `check` reports `change_streams` as failed.
- [ ] Recommended: oplog window of 7 days or more, so a paused job can resume.

## Steps

1. Write `source.json` in the config folder (example below). Every field:
   [references/config.md](references/config.md).
2. `check` the source, then `discover` (`olake-protocol` steps 2 to 4).
3. In `selected_streams.json`, set the sync mode per stream (`incremental` also needs `cursor_field`).
   Set `"normalization": true` to get one column per top-level field. The default (`false`)
   writes each document as one JSON string column `data`.
4. Sync, then rerun with `--state` (`olake-protocol` steps 6 and 7).

```json
{
  "hosts": ["<HOST>:27017"],
  "database": "<DATABASE>",
  "username": "<USERNAME>",
  "password": "<PASSWORD>",
  "authdb": "admin",
  "replica_set": "<REPLICA_SET>",
  "srv": false,
  "update_method": { "type": "Standalone" },
  "max_threads": 3
}
```

CDC: replace `update_method` with `{ "type": "CDC" }`. Atlas: `"srv": true`, `"hosts": ["<CLUSTER>.mongodb.net"]`,
no `replica_set`.

## Verify

- `check` prints `"status":"SUCCEEDED"`; with CDC, `change_streams` has `"passed": true`.
- Row count on the destination equals `db.<collection>.countDocuments()` on the source.
- CDC: insert a document, rerun with `--state`, and find it on the destination with `_op_type` = `c`.

## Common errors

| Error | Cause | Fix |
| --- | --- | --- |
| `check`: `change_streams` `"passed": false` | Standalone `mongod` | Run a replica set (a one-node set works), or use `Standalone` mode. |
| `failed to connect to MongoDB` | Host, `authdb` or `srv` wrong | Atlas: `"srv": true`, no `replica_set`; `authdb` is usually `admin`. |
| `change stream error` with `ChangeStreamHistoryLost` | Oplog rolled past the saved resume token | `clear-destination` for the stream, then sync; raise the oplog window. |
| Destination table has one `data` column | `normalization` defaults to `false` for MongoDB | Set `"normalization": true` (Step 3). |

## Next

- The run, reruns and state: `olake-protocol`.
- Sync modes in general: `olake-driver-abstract`.
- Destination setup: `olake-destination-abstract`, then the destination skill.

## Rules

- Use `<PASSWORD>` placeholders; never print secrets.
