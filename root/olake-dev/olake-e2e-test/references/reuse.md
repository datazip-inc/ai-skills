# Reuse a stack

A stack is everything one run directory started: the OLake compose project `olake-dev-<run-id>`, the test source and destination, the built images, the managed worktrees, and the sources, destinations and jobs created in OLake.
One stack serves many tests.
A follow-up (a question, a config change, a code change, another sync) reuses the active stack, and only a test that needs fresh state starts a new one.

## Find the active stack

Only one stack can run at a time, because the container names and ports are fixed.

```bash
docker compose ls -a --filter name=olake-dev-
ls -t ~/.olake-dev/runs/ | head -3
```

The active stack is the `olake-dev-<run-id>` project that is running, with its run directory `~/.olake-dev/runs/<run-id>/`.
Its `stack.md` lists what the next test needs (see below).
A running `olake-dev-*` project with no run directory, or a project with any other name, is not the skill's to reuse: treat it as the user's.

## Reuse or start fresh

| Situation | Action |
| --- | --- |
| A question about the last result, its logs or its data | Reuse. Answer from the run directory and the running stack; change nothing |
| Same code, new test: another table, config or sync mode | Reuse. New tables and a new job for the new case, named after the test, because a job's state and namespace carry over to its next sync |
| A rerun with state, or an incremental or CDC follow-up | Reuse, on the same job and tables: carrying the state over is what the test checks |
| Code changed in a repo the stack already built | Reuse. Rebuild only that image with its new run tag, update `compose.override.yml`, and run `up -d`: compose recreates only the changed services and keeps the volumes |
| A driver was rebuilt | As above, and also set the new tag in `CUSTOM_DRIVER_VERSION` (this recreates `olake-ui`). Create a new source and job at the new version; existing jobs keep the old one |
| A repo that ran a release image now needs a build | Reuse. Build it and switch that service's image, as above |
| Versions to compare | Reuse, as in Compare versions below |
| A different set of branches | Reuse: rebuild what changed, as above |
| The user asks for a fresh, clean or new stack, or "from scratch" | Fresh |
| No active stack, or it is unhealthy after one restart | Fresh |

Reuse is the default; a fresh stack starts only when the user asks for one or no usable stack exists.
Say which in the intake message ("reusing stack `<run-id>`"), so the user can ask for a fresh one.
When the stack cannot show what was asked, say why and ask for a fresh stack: a first install, signup, migrations from an empty database, or olake-ui moving to an older commit than the stack has run (its database may hold newer migrations).
Before a fresh stack, tear down the old one (`SKILL.md`, Cleanup), after the user says it can go.

## Compare versions

Same stack, unless the user asks for fresh stacks.
Every version runs the same cases on the same seed tables, with its own source and job, so each writes to its own Iceberg namespace.

| What differs | How |
| --- | --- |
| Driver (olake) | Side by side: one source and job on the baseline tag, one on the change's tag. `CUSTOM_DRIVER_VERSION` holds the change's tag; a baseline that is a published release is listed anyway. A baseline built from source gets its own run tag and is set through the API <!-- TODO[BEFORE_MERGE]: olake-ui#9 --> |
| UI or worker (olake-ui, olake-helm) | One after the other: run the baseline first, then switch to the change's images with `up -d` and run the same cases on new jobs. Baseline first, because moving forward runs the migrations normally |

When the user asks for fresh stacks: one per version, one after the other, with the same seed and configs, and tear down between them.
Report every difference in row count, schema and values, per case.

## Keep tests apart in one stack

- Each test gets a number `<NN>` and a short name, starting at `01`.
  Its files go in `<test-dir>` = `<run-dir>/tests/<NN>-<name>/`: seed, configs, request and result files, dumps, and `report.md`.
  Stack-level files stay in `<run-dir>`: `stack.md`, `compose.override.yml`, the cookie jar, build logs, and `olake-data/` (driver runs of every test; find a test's tasks by `containerName` (the workflow directory) in the worker log line `running container`).
- Each test seeds its own tables, or reuses the previous test's tables only when it means to (for example a rerun with state).
- Job and source names carry the test number, so each job writes to its own Iceberg namespace.

## `stack.md`

Write it when the stack comes up, and update it after every test:

- Compose project, compose files and override path.
- Per repo: code source, ref, SHA, and image tag (run tag or pinned release).
- Test source and destination: containers, ports, credentials file path.
- OLake objects: source, destination and job IDs and names, per test.
- Tables in the test source, per test.
- The last test number.
