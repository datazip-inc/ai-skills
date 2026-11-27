---
name: olake-deploy-docker-compose
description: "Run OLake with its web UI on one machine with docker compose: start, login, admin user, encryption key, data folder, ports, logs, upgrade, reset, teardown. Use for OLake UI on a laptop or VM, or when olake-ui does not start, log in or reach a source."
metadata:
  parent: olake-protocol
  status: experimental
---

# OLake with Docker Compose

The compose stack runs the OLake UI, a Temporal worker and Temporal on one Docker host. The worker
starts one driver container (`olakego/source-<driver>`) per `check`, `discover` and `sync`, through
the host's Docker socket. The CLI flow without a UI is in `olake-protocol`.

Pinned to [olake-ui `v0.9.3`](https://github.com/datazip-inc/olake-ui/blob/v0.9.3/docker-compose-v1.yml)
and the [install docs](https://olake.io/docs/install/olake-ui). The images use the `latest` tag.

## When to use

- The user wants OLake with the web UI on a laptop or one VM.
- `olake-ui` does not come up, login fails, or a job in the UI cannot reach its source.
- Upgrade, reset or removal of a compose install.
- Not covered: Kubernetes → `olake-deploy-helm`; source and destination settings → the driver and
  destination skills; CLI-only runs → `olake-protocol`.

## Inputs to collect

| Input | Default | Ask when |
| --- | --- | --- |
| Folder to run from | current directory | Always: `./olake-data` is created there. |
| Admin user, password, email | `admin` / `password` / `admin@example.com` | Anything beyond a local test. |
| Encryption key (`OLAKE_SECRET_KEY`) | `""` (no encryption) | Anything beyond a local test. A passphrase or an AWS KMS key ARN. |
| External Postgres or Temporal | built-in containers | The user has a managed Postgres or Temporal Cloud. |
| Private registry | `docker.io` | The host cannot pull from Docker Hub. |
| Host port for the UI | `8000` | `8000` is taken. |

## Prerequisites

- [ ] Docker with Compose v2 (`docker compose version`). Docker Desktop on macOS and Windows.
- [ ] Docker resources: minimum 8 vCPU and 16 GB RAM, recommended 16 vCPU and 32 GB RAM.
- [ ] Port `8000` free: `lsof -i :8000`. Change it in [references/ports.md](references/ports.md).
- [ ] Linux: the user is in the `docker` group, or runs with `sudo`.
- [ ] Outbound access to the registry: the worker pulls a driver image on the first job of each type.

## Steps

1. Pick the folder, then `cd` into it. `${PWD}/olake-data` is bound into the containers, so run every
   later `docker compose` command from the same folder.
2. Local test with defaults, one command:
   ```bash
   curl -sSL https://raw.githubusercontent.com/datazip-inc/olake-ui/master/docker-compose-v1.yml | docker compose -f - up -d
   ```
3. Anything else: download the file, edit it, then start it.
   ```bash
   curl -sSL -o docker-compose.yml https://raw.githubusercontent.com/datazip-inc/olake-ui/master/docker-compose-v1.yml
   ```
   Edit the anchors at the top of the file:
   ```yaml
   x-signup-defaults:
     username: &defaultUsername "<ADMIN_USER>"
     password: &defaultPassword "<ADMIN_PASSWORD>"
     email: &defaultEmail "<ADMIN_EMAIL>"

   x-encryption:
     key: &encryptionKey "<PASSPHRASE_OR_KMS_ARN>"
   ```
   Then `docker compose up -d`. Other settings: [references/config.md](references/config.md).
4. Wait for health: `docker compose ps` shows `olake-ui` as `healthy`. `olake-signup-init` exits 0
   after it creates the admin user. Temporal schema setup runs first and takes a minute.
5. Open `http://localhost:8000` and log in with the admin user.
6. Create a source in the UI. The driver container is not on the compose network: reach a database
   on the host with `host.docker.internal` (Docker Desktop) or the host's IP (Linux).
   [references/ports.md](references/ports.md#reaching-sources).
7. Create a destination and a job, then run it. Follow a run in
   [references/logs.md](references/logs.md).

## Verify

- `docker compose ps`: `olake-ui`, `olake-temporal-worker`, `temporal`, `temporal-postgresql` are
  `running`; `olake-ui` is `healthy`.
- `docker compose logs signup-init` ends with
  `signup-init: User '<user>' creation request successful`.
- `curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8000` prints `200`.
- After a test connection in the UI, `docker ps -a` lists a container from `olakego/source-<driver>`,
  and `./olake-data` has a new folder.

## Upgrade

The images use `latest` with `pull_policy: always`, so `up` pulls new images. From the same folder:

```bash
curl -sSL https://raw.githubusercontent.com/datazip-inc/olake-ui/master/docker-compose-v1.yml | docker compose -f - down && \
curl -sSL https://raw.githubusercontent.com/datazip-inc/olake-ui/master/docker-compose-v1.yml | docker compose -f - up -d
```

`down` without `-v` keeps `./olake-data` and the named volumes. With an edited local file, download
the new file, carry the edits over, then `docker compose down && docker compose up -d`.

Legacy stack (`docker-compose.yml` with Elasticsearch): moving to `docker-compose-v1.yml` keeps jobs,
but old job logs and run history in Elasticsearch are not shown after the move. Ask the user first.

## Stop, reset, remove

| Goal | Command | Keeps data |
| --- | --- | --- |
| Stop | `docker compose stop` | yes |
| Remove containers | `docker compose down` | yes: `./olake-data` and volumes stay |
| Reset everything | `docker compose down -v`, then `rm -rf ./olake-data` | **no** |

`down -v` deletes `temporal-postgresql-data`: every source, destination, job, run history and the
admin user. Removing `./olake-data` deletes state files and logs. Confirm with the user and offer a
backup first ([references/volumes.md](references/volumes.md#backup)).

## Common errors

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Bind for 0.0.0.0:8000 failed: port is already allocated` | Another process holds `8000` | Free it, or change the host port ([ports.md](references/ports.md)). |
| `olake-ui` stays `starting`, then `unhealthy` | Postgres or Temporal not ready, or low memory | `docker compose logs temporal temporal-postgresql`; raise Docker memory. |
| `signup-init` exits 1 with `creation request FAILED (HTTP 409)` | The user already exists from an earlier start | Expected on a rerun; log in with the existing user. |
| Login fails after an edit of the credentials | `signup-init` only creates the user on first start | Use the first credentials, or reset (deletes data). |
| Test connection: `connection refused` to `localhost` | `localhost` is the driver container | `host.docker.internal` or the host IP. |
| `permission denied` on `/var/run/docker.sock` or `./olake-data` | Linux user and file permissions | Add the user to `docker`; check ownership of `./olake-data`. |
| Jobs run but the UI shows no history after a move from the legacy stack | History stayed in Elasticsearch | Expected; see Upgrade. |

## Next

- Settings in the compose file: [references/config.md](references/config.md).
- Where files and data live: [references/volumes.md](references/volumes.md).
- Logs of the stack and of a job run: [references/logs.md](references/logs.md).
- Source and destination settings: the `olake-driver-*` and `olake-destination-*` skills.

## Rules

- Never run `docker compose down -v` or delete `./olake-data` without the user's explicit yes.
- Change the default admin password and set an encryption key before real credentials go in.
- Keep the encryption key: configs saved with it cannot be read without it.
- Write secrets as placeholders (`<ADMIN_PASSWORD>`); never print them from the compose file.
- Remove only containers this stack created; never prune other Docker resources.
