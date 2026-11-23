# Errors

Errors seen in past tests, by the message or symptom that shows first.
Each fix is complete here: no other file is needed to apply it.
List only errors whose message does not point at the cause; a rule that a step already enforces lives in that step, not here.
When a test hits an error that is not listed and fits that bar, add it with its cause and fix.

## Build

| Message or symptom | Cause | Fix |
| --- | --- | --- |
| `Non-readable POM .../olake-iceberg-java-writer/dependency-reduced-pom.xml: input contained no data`, then `make: *** [.../olake-iceberg-java-writer-0.0.1-SNAPSHOT.jar] Error 1` | Two driver images were built at once from one olake checkout; both compile the Java writer in the same folder | Build the driver images of one checkout one at a time. Rerun the failed build alone |

## Deploy

| Message or symptom | Cause | Fix |
| --- | --- | --- |
| `Conflict. The container name "/olake-ui" is already in use` (or another fixed name) | A stack with the same fixed container names exists, often the user's own | Remove it if it has exited and the test needs it gone; ask before stopping a running one |
| `kind load docker-image` fails with `ctr: content digest sha256:...: not found` | Docker Desktop's image store keeps only the pulled platform of a multi-platform image, and kind imports all platforms | Save one platform and load the archive: `docker save --platform linux/<arch> -o <file>.tar <image>` then `kind load image-archive <file>.tar --name <cluster>` |
| A pod stays in `ErrImagePull` or `ImagePullBackOff` | The image is not in the kind node, or its pull policy is `Always` (the chart default for the UI and the worker), so Kubernetes pulls a tag that exists only locally | `docker exec <cluster>-control-plane crictl images \| grep olakego`: load a missing image as in the line above. For a listed one, set `pullPolicy: IfNotPresent` for it in the values overlay and run `helm upgrade` |
| `curl: (7) Failed to connect to localhost port 8000` on Kubernetes | The port-forward stopped, usually because the UI pod restarted | Start the port-forward again and log in again |

## API

| Message or symptom | Cause | Fix |
| --- | --- | --- |
| HTTP 401 after a login that succeeded | Python's `http.cookiejar` skips the `#HttpOnly_` lines that `curl -c` writes | Use `scripts/api-op.py`, which reads the cookie file directly |
| `failed to validate request: EOF` | The endpoint needs a JSON body | Send the body that `<olake-ui>/api-contract.md` documents for that endpoint |
| `invalid destination type has been passed []` or `[iceberg]` | The destination config is flat | Wrap it: `{"type": "ICEBERG", "writer": {...}}` |
| Destination test fails pulling `olakego/source-mysql:<version>` | The UI reads the destination spec from the mysql driver image at that version. `source_type` or `source_version` is missing, or no mysql image exists at that version | Send `source_type` and `source_version`. When olake was built, also build `olakego/source-mysql:<tag>` |
| `Field validation for 'Frequency' failed on the 'required' tag` | Job created with an empty `frequency` | Use `0 0 1 1 *` and start runs with `POST <api>/jobs/<id>/sync` |
| `required CDC prerequisites not met: replication_slot` (Postgres) | The source config has `update_method` with CDC fields, which turns on the CDC checks | For full refresh or incremental, leave `update_method` out or set `{"type": "Standalone"}`. For CDC, create the slot and publication first |

## Sync and verify

| Message or symptom | Cause | Fix |
| --- | --- | --- |
| `Sync failed: connector exited with code 1. See Sync logs for the error.` (in `logs/worker.log`) | The driver failed; the worker only reports the exit code | Read `logs/sync_<time>/olake.log` in the same workflow directory for the error line |
| The second of two Iceberg syncs fails or hangs at writer start | Both use the Java writer port 50051 | Run the syncs one after another |
| `--max-discover-threads` has no effect | olake-ui from before the fix drops the flag for a driver tag that is not semver, even with `CUSTOM_DRIVER_VERSION` set (`SupportsMaxDiscoverThreads`). A pinned olake-ui release with a locally built driver hits this | Test the flag with an olake-ui that has the fix; on an older olake-ui, report it as NOT RUN and say why |
