# Errors

Errors seen in past tests, by the message or symptom that shows first.
Each fix is complete here: no other file is needed to apply it.
When a test hits an error that is not listed, add it with its cause and fix.

## Build

| Message or symptom | Cause | Fix |
| --- | --- | --- |
| `Non-readable POM .../olake-iceberg-java-writer/dependency-reduced-pom.xml: input contained no data`, then `make: *** [.../olake-iceberg-java-writer-0.0.1-SNAPSHOT.jar] Error 1` | Two driver images were built at once from one olake checkout; both compile the Java writer in the same folder | Build the driver images of one checkout one at a time. Rerun the failed build alone <!-- TODO[BEFORE_MERGE]: olake#1 --> |
| A build "finished" but the image is old | The build did not run; an older image with the same tag remained | Compare the image's `olake.test.sha` and `olake.test.diff` labels with the values recorded before the build, and rebuild |
| `git status` shows `go.work.sum` or other tracked files changed after a build | Builds edit tracked files | Run `scripts/checkout-info.sh --compare` against the preflight snapshot and restore only its `REVERT` files <!-- TODO[BEFORE_MERGE]: olake#2 --> |

## Deploy

| Message or symptom | Cause | Fix |
| --- | --- | --- |
| `Conflict. The container name "/olake-ui" is already in use` (or another fixed name) | A stack with the same fixed container names exists | Remove it if it has exited and the test needs it gone; ask before stopping a running one |
| The UI shows jobs, sources or destinations that no test in `stack.md` created | The compose project name is shared with a stack that is not the skill's, so its volumes were mounted | Stop. Bring the stack up with its own project, `-p olake-dev-<run-id>`. Tell the user which volume was touched |
| `spark-sql` fails on the first query after the first boot | Jar download race in `spark-iceberg` | `docker restart spark-iceberg`, then query again |
| Worker S3 log storage check fails with a low tag such as `v0.0.0-dev` | The worker gates S3 log storage on the version | Rebuild with the run tag `v100.0.0-test-<git-sha>` <!-- TODO[BEFORE_MERGE]: olake-helm#1 --> |

## API

| Message or symptom | Cause | Fix |
| --- | --- | --- |
| HTTP 401 after a login that succeeded | Python's `http.cookiejar` skips the `#HttpOnly_` lines that `curl -c` writes | Use `scripts/api-op.py`, which reads the cookie file directly |
| `failed to validate request: EOF` | The endpoint needs a JSON body | Send the body that `<olake-ui>/api-contract.md` documents for that endpoint |
| `invalid destination type has been passed []` or `[iceberg]` | The destination config is flat | Wrap it: `{"type": "ICEBERG", "writer": {...}}` <!-- TODO[BEFORE_MERGE]: olake-ui#4 --> |
| Destination test fails pulling `olakego/source-mysql:<version>` | The UI reads the destination spec from the mysql driver image at that version. `source_type` or `source_version` is missing, or no mysql image exists at that version | Send `source_type` and `source_version`. When olake was built, also build `olakego/source-mysql:<tag>` <!-- TODO[BEFORE_MERGE]: olake-ui#3, olake-ui#6 --> |
| `Field validation for 'Frequency' failed on the 'required' tag` | Job created with an empty `frequency` | Use `0 0 1 1 *` and start runs with `POST <api>/jobs/<id>/sync` <!-- TODO[BEFORE_MERGE]: olake-ui#5 --> |
| `required CDC prerequisites not met: replication_slot` (Postgres) | The source config has `update_method` with CDC fields, which turns on the CDC checks | For full refresh or incremental, leave `update_method` out or set `{"type": "Standalone"}`. For CDC, create the slot and publication first |
| Operation `succeeded` but the connection did not work | The operation status only means the container ran | Read `data.connection_result.status` in the result: pass on `SUCCEEDED` only |

## Sync and verify

| Message or symptom | Cause | Fix |
| --- | --- | --- |
| `Sync failed: connector exited with code 1. See Sync logs for the error.` (in `logs/worker.log`) | The driver failed; the worker only reports the exit code | Read `logs/sync_<time>/olake.log` in the same workflow directory for the error line |
| A config option has no effect, with no error | Unknown config keys are ignored silently | Take the key name from the spec of the version under test, then find the log line that shows the option ran |
| The second of two Iceberg syncs fails or hangs at writer start | Both use the Java writer port 50051 | Run the syncs one after another |
| `--max-discover-threads` has no effect | The driver tag is not a version number, so the flag is dropped | Rebuild with the run tag `v100.0.0-test-<git-sha>` <!-- TODO[BEFORE_MERGE]: olake#3 --> |
| NULL and an empty string look the same in a comparison | The dump prints NULL as empty | Dump with `psql -P null=NULL` |
