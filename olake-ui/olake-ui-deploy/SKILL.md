---
name: olake-ui-deploy
description: "Run the OLake UI stack (web UI and API, Temporal, worker) on one machine with docker compose: install it at a pinned version, log in, change its settings (admin user, data folder, encryption key, S3 log storage, custom CA and client keys for drivers, private registry, usage stats), upgrade it, read its logs and tear it down. Use when the user wants to install, start, upgrade, configure or remove OLake UI on a laptop, server or VM with docker compose, or asks why the OLake UI stack does not come up. Not for Kubernetes, creating sources, destinations or jobs (olake-ui-manage), or testing OLake code changes (olake-e2e-test)."
metadata:
  olake_version: "olake-ui v0.9.3, worker v0.5.1"
  verified: "2026-11-23: install, settings (usage stats, data folder, host port), upgrade from v0.9.2 and v0.5.0 with data kept, tear down"
  status: experimental
---

# Run OLake UI with docker compose

The stack is olake-ui's `docker-compose-v1.yml`:

| Service | Container | Port | Role |
| --- | --- | --- | --- |
| `olake-ui` | `olake-ui` | 8000 | Web UI and REST API on one port |
| `temporal-worker` | `olake-temporal-worker` | - | Runs each task (spec, test connection, discover, sync) as a driver container on the host's Docker |
| `temporal` | `temporal` | - | Workflow engine |
| `postgresql` | `temporal-postgresql` | - | Temporal's database and the OLake database (users, sources, destinations, jobs), in the volume `<project>_temporal-postgresql-data` |
| `temporal-schema-migrate`, `temporal-create-namespace`, `signup-init` | same names | - | One-shots at start; `signup-init` creates the admin user |
| `temporal-ui` | `temporal-ui` | 8081 | Only with `--profile debug` |

For each task, olake-ui writes the configs to a job folder in `olake-data/` and starts a Temporal workflow; the worker runs the driver container on that folder, and the driver writes its state, stats and logs back into it.
The flow, where each kind of state lives, and why some settings go on both services: [../references/architecture.md](../references/architecture.md).
The `fusion` profile (table maintenance) is not covered here.

## When to use

- Install, start, configure, upgrade or remove OLake UI with docker compose.
- The stack does not come up, or the login fails.
- Not covered: sources, destinations and jobs: `olake-ui-manage` (this plugin); a code change under test: `olake-e2e-test` (plugin `olake-dev`); Kubernetes: `olake-helm-deploy`, in the `olake-helm` plugin of this marketplace (`/plugin install olake-helm@olake-ai-skills`).

## Inputs to collect

| Input | Default |
| --- | --- |
| Folder for the stack | `~/olake`. Its name is the compose project name, so every command runs from it |
| Version | The newest release of olake-ui and of the worker (olake-helm), found in step 1 |
| Settings | None. Each one the user wants: [references/settings.md](references/settings.md) |

## Prerequisites

- [ ] `docker compose version` shows v2, and Docker has about 0.5 GB free for the stack, plus room for each running driver container.
- [ ] Port 8000 is free: `lsof -nP -iTCP:8000 -sTCP:LISTEN` prints nothing.
  On macOS Docker starts even when another process holds `127.0.0.1:8000`, and `localhost:8000` then reaches that process, not OLake.
- [ ] No container holds a name from the table above: `docker ps -a --format '{{.Names}}' | grep -E '^(olake-|temporal)'` prints nothing.
  The names are fixed, so one docker host runs one OLake UI stack. Ask before removing a container the user owns.

## Steps

1. Find the newest release of each image:

   ```bash
   for repo in olake-ui olake-helm; do
     git ls-remote --tags --refs "https://github.com/datazip-inc/$repo" 'v*' | sed 's#.*refs/tags/##' \
       | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1
   done
   ```

   The first line is `<ui-tag>` (image `olakego/ui`), the second `<worker-tag>` (image `olakego/ui-worker`).
2. Get the compose file of that release, in the stack's folder:

   ```bash
   mkdir -p ~/olake && cd ~/olake
   curl -fsSL https://raw.githubusercontent.com/datazip-inc/olake-ui/<ui-tag>/docker-compose-v1.yml -o docker-compose-v1.yml
   ```

3. Pin the images in `compose.override.yml`, next to it; the compose file itself names `latest`, pulled again on every start:

   ```yaml
   services:
     olake-ui:
       image: ${CONTAINER_REGISTRY_BASE:-docker.io}/olakego/ui:<ui-tag>
     temporal-worker:
       image: ${CONTAINER_REGISTRY_BASE:-docker.io}/olakego/ui-worker:<worker-tag>
   ```

   Every setting goes in this file too ([references/settings.md](references/settings.md)), so an upgrade never loses it.
4. Start, then wait with the gate:

   ```bash
   docker compose -f docker-compose-v1.yml -f compose.override.yml up -d
   ${CLAUDE_SKILL_DIR}/scripts/compose-gate.sh <project> ~/olake
   ```

   `<project>` is the folder name (`olake`).
   The gate polls every 10 seconds and stops at the first broken state; it ends with `GATE PASS` or `GATE FAIL: <reason>`.
5. Open `http://localhost:8000` and log in with `admin` / `password`, or the admin user set in the settings.

## Verify

- The gate printed `login=200` and `GATE PASS`.
- Its `image` lines show `<ui-tag>` and `<worker-tag>`.

## Upgrade

1. Find the new tags (step 1), download the new release's compose file over the old one (step 2), and set the new tags in `compose.override.yml`.
2. Run step 4 again: compose recreates the changed services and keeps the volume and `olake-data/`.

Never move to an older release: the OLake database may hold migrations the older server does not know.

## Logs

| What | Command |
| --- | --- |
| UI and API | `docker logs --since 10m olake-ui 2>&1 \| grep -i -E 'error\|fail' \| cut -c1-250` |
| Worker start-up and Temporal connection | `docker logs --since 10m olake-temporal-worker 2>&1 \| grep -i -E 'error\|fail' \| cut -c1-250` |
| Which driver image each task ran | `docker logs olake-temporal-worker 2>&1 \| grep 'running container' \| cut -c1-250` |
| One task's files | `olake-data/<workflow-dir>/`: `logs/worker.log`, and for a sync `logs/sync_<time>/olake.log`, `state.json`, `stats.json` |

The worker removes each driver container when its task ends, so its files in `olake-data/` are the record.

## Tear down

```bash
docker compose -f docker-compose-v1.yml -f compose.override.yml down      # stops the stack, keeps all data
docker compose -f docker-compose-v1.yml -f compose.override.yml down -v   # also deletes the OLake database
```

`down -v` deletes every user, source, destination and job; ask first.
`olake-data/` stays until the user deletes it.

## Common errors

| Error | Cause | Fix |
| --- | --- | --- |
| `Conflict. The container name "/olake-ui" is already in use` | Another OLake UI stack, or a stopped one, holds the fixed names | Find its folder (`docker inspect olake-ui --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'`) and run `down` there, after the user agrees |
| `localhost:8000` answers, but with another OLake or another app | Another process holds port 8000, for example a `kubectl port-forward`; Docker on macOS binds beside it | Stop it, or map another host port (settings) |
| `signup-init` exited 1 with `HTTP 409` and `Username already exists`, after a restart | `signup-init` runs on every start; the admin user already exists | Nothing to fix; the gate accepts it |
| The UI shows no sources or jobs after an upgrade | The stack started from another folder, so it made a new, empty volume | Start it from the original folder |

## Next

- Create sources, destinations and jobs: `olake-ui-manage`.
- Run on Kubernetes instead: `olake-helm-deploy` (plugin `olake-helm`).

## Rules

- Run every command from the stack's folder.
- Keep settings in `compose.override.yml`, never in the downloaded compose file.
- Set the encryption key before the first source is created, and never change it afterwards (settings).
- Ask before `down -v`, and before stopping or removing a container this stack did not create.
