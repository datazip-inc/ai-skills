# Changes needed in other repos

Fixes in the OLake code repos that would let the skills point to the owner's docs instead of carrying the fact themselves, or remove a workaround.
Each item names where the skill carries it today.
Item IDs are `<repo>#<number>`, for example `olake-ui#3` is item 3 under olake-ui.

Every place in the skills that carries a workaround has a marker with its item ID:

```markdown
<!-- TODO[BEFORE_MERGE]: olake-ui#3 -->
```

List them all before a merge:

```bash
grep -rn 'TODO\[BEFORE_MERGE\]' --include='*.md' . | grep -v '^./TODO.md'
```

When a fix lands, remove the item here, and the workaround and its marker in the skill.

## olake-ui

1. `api-contract.md`: auth is a session cookie from `POST /login`, but every endpoint shows `Authorization: Bearer <token>`.
   Skill: the login command in `root/olake-dev/olake-e2e-test/references/docker-compose.md`, section 3, and `scripts/api-op.py`.
2. `api-contract.md`: spec, test connection and discover are asynchronous (`202` with `operation_id`, as the "Async operations" section says), but their own sections still show a direct response.
   Skill: `scripts/api-op.py`, which posts and polls.
3. `api-contract.md`, "Test Destination": the body also needs `source_type` and `source_version`, because the destination spec is read from that driver's image.
   Skill: `references/errors.md`.
4. `api-contract.md`, destinations: document the `config` shape `{"type": "ICEBERG", "writer": {...}}`. Sent flat, the test fails with `invalid destination type has been passed []`.
   Skill: `references/errors.md`.
5. `api-contract.md`, "Create Job": `frequency` is required and an empty value is rejected (`Field validation for 'Frequency' failed on the 'required' tag`).
   Skill: `references/errors.md`, and the `frequency` line in `references/docker-compose.md`, section 3.
6. `GetDestinationSpec` reads the destination spec from the `olakego/source-mysql` image at the run's version, whatever the source.
   Every test that builds olake must also build the mysql image.
   Skill: `SKILL.md`, step 3 (Build).
7. `docker-compose-v1.yml`: `temporal-worker` has no healthcheck, so a deploy gate can only check that it is running.
   Skill: `references/docker-compose.md`, section 2 (Gate).
8. `docker-compose-v1.yml`: fixed `container_name` values and fixed host ports (`8000`) stop a second stack from running next to an existing one.
   Container names from the project name, and ports from variables (`${OLAKE_UI_PORT:-8000}:8000`), would let the skill run beside a user's own stack.
   Skill: `SKILL.md` preflight, `references/docker-compose.md`.
9. `CUSTOM_DRIVER_VERSION` takes one tag, so only one locally built driver version shows in the UI.
   A list would let a version comparison use two local builds without going through the API.
   Skill: `references/reuse.md`, "Compare versions".

## olake

1. Driver image builds from one checkout cannot run in parallel: each runs the same Maven build of the Iceberg Java writer in the same folder, and parallel runs corrupt `dependency-reduced-pom.xml`.
   Building the writer jar once (or per build in its own folder) would remove the rule.
   Skill: `SKILL.md` step 3, `references/pitfalls.md`, `references/errors.md`.
2. Builds change the tracked `go.work.sum`.
   Skill: `references/pitfalls.md`, and the revert step in `SKILL.md` step 3.
3. A driver tag that is not semver silently drops `--max-discover-threads` from discover.
   A warning in the log would make the cause visible.
   Skill: `references/pitfalls.md`, `references/errors.md`.
4. The test stacks (`drivers/<driver>/docker-compose.yml`, `destination/iceberg/local-test/docker-compose.yml`) have fixed host ports, container names and project names.
   Ports from variables would let a run move a port that something else on the machine holds.
   Skill: `references/docker-compose.md`, section 1.

## olake-helm

1. The worker's S3 log storage check fails for a low version such as `v0.0.0-dev`, with no bypass for development builds.
   Skill: `SKILL.md` step 3 (run tag), `references/pitfalls.md`.
