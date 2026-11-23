# OLake API

The same for docker compose and Kubernetes stacks: on Kubernetes, the UI service is port-forwarded to `localhost:8000`.

Base URL `http://localhost:8000/api/v1/project/123` (`<api>` below).
The server accepts any project id, but the UI always uses `123` (`<olake-ui>/ui/src/config/apiConfig.ts`), so sources, destinations and jobs made under another id do not show in the UI.
The base URL in `api-contract.md` (port 8080, project id `olake`) is out of date: use this one.
Every endpoint, request body and response is in `<olake-ui>/api-contract.md`, in the code under test.
It is about 1,260 lines: list its sections with `grep -n '^###' <olake-ui>/api-contract.md` and read only the section of the call being made.
Keep the cookie jar in `<run-dir>`, and every request and result file in `<test-dir>`.

The deploy gate logs in and writes the cookie jar; pass `-b <run-dir>/cookies.txt` on every later `curl` call.
To log in again (a new stack, or an expired session):

```bash
curl -s -c <run-dir>/cookies.txt -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"password"}' http://localhost:8000/login
```

The test calls, in order: source versions, source and destination spec, source and destination test, discover (`sources/streams` with `job_id` -1), create job, job sync, job tasks.
Run the asynchronous ones with the bundled script, which posts, polls and saves the result:

```bash
python3 -I ${CLAUDE_SKILL_DIR}/scripts/api-op.py <run-dir> sources/test <test-dir>/body-src-test.json <test-dir>/res-src-test.json 120
```

- A spec result holds the JSON schema at `data.spec.jsonschema`.
  The Iceberg writer's keys for each catalog are under `properties.writer.dependencies.catalog_type.oneOf`, one entry per `catalog_type` value.
- For discover, take `available_streams` and `selected_streams` from the result, set `sync_mode` on every selected entry, and send both back as JSON strings on job create.
- Create the job with `frequency` `0 0 1 1 *` and start each run with job sync, so nothing runs on a schedule.
- Use the run tag as the driver `version` when a driver was built (it is listed because of `CUSTOM_DRIVER_VERSION`), otherwise the pinned release tag.
