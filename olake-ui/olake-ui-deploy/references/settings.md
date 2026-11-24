# Settings

Every setting goes in `compose.override.yml`, next to `docker-compose-v1.yml`, and takes effect with the start command of step 4.
**The** downloaded compose file is never edited: an upgrade replaces it, and a setting written there would be lost.
Compose merges the override into the compose file: an `environment` key replaces the same key, and a volume replaces the one with the same container path.
Read from olake-ui `docker-compose-v1.yml` and `server/conf/app.yaml` at v0.9.3, and the worker's `constants/env.go` at olake-helm v0.5.1.

## Settings for both services

Many settings must reach both `olake-ui` and `temporal-worker`, because both touch the same configs and job folder; [../../references/architecture.md](../../references/architecture.md) says why, per setting.
YAML anchors only work inside one file, so the override defines its own shared block, the way the compose file does with `x-envs`.
Add it once, the first time a shared setting is needed:

```yaml
x-olake-env: &olakeEnv
  TELEMETRY_DISABLED: "true"

services:
  olake-ui:
    image: ...                  # the pin from step 3 stays
    environment: *olakeEnv
  temporal-worker:
    image: ...
    environment: *olakeEnv
```

Each shared setting below is then one or more lines under `x-olake-env`.
A setting for one service only goes under that service, next to `environment: *olakeEnv`, in a `<<: *olakeEnv` merge:

```yaml
services:
  olake-ui:
    environment:
      <<: *olakeEnv
      USERNAME: "<user>"
```

## Secrets in `.env`

The release ships no `.env`; create it in the stack's folder when a setting below needs a secret.
Compose reads `.env` from the project folder, which is the folder of the first `-f` file, here the stack's folder.
It fills each `${NAME}` in both compose files from it; a variable of the same name set in the shell wins over the file.
Only names the compose files reference reach a container; the file itself is never mounted.
Keep it readable only by its owner, and out of any repository:

```bash
cd ~/olake
touch .env && chmod 600 .env
printf 'OLAKE_SECRET_KEY=%s\n' "$(openssl rand -hex 32)" >> .env   # one line per secret
```

Keep a copy of `.env` outside the stack's folder: without the encryption key, the stored configs cannot be read.

## Admin user

For `olake-ui` and `signup-init` only.
Set it before the first start: `signup-init` creates the user once, on an empty database.

```yaml
services:
  olake-ui:
    environment:
      <<: *olakeEnv
      USERNAME: "<user>"
      PASSWORD: "<PASSWORD>"
  signup-init:
    environment:
      USERNAME: "<user>"
      PASSWORD: "<PASSWORD>"
      EMAIL: "<email>"
```

## Encryption key for stored configs

`OLAKE_SECRET_KEY` encrypts the source and destination configs in the OLake database.

| Value | Mode |
| --- | --- |
| `""` (the default) | No encryption. Development only |
| Starts with `arn:aws:kms:` | AWS KMS; `olake-ui` needs AWS credentials for that key |
| Any other string | AES-256-GCM, with a key derived from the string |

Set it before the first source is created.
Never change it afterwards: configs saved under the old key can no longer be read.
Put the value in `.env` (see above), not in the override, and add to `x-olake-env`:

```yaml
x-olake-env: &olakeEnv
  OLAKE_SECRET_KEY: ${OLAKE_SECRET_KEY:?set OLAKE_SECRET_KEY in .env}
```

The `:?` form stops the start when `.env` is missing, instead of starting with no key and leaving the stored configs unreadable.

## Data folder

Task files go to `./olake-data` by default.
To move them, change the host path in three places: `PERSISTENT_DIR`, which the worker passes to each driver container, and the bind mount of both services.
The folder must exist and be writable by Docker.

```yaml
x-olake-env: &olakeEnv
  PERSISTENT_DIR: /data/olake

x-olake-data: &olakeData
  type: bind
  source: /data/olake
  target: /tmp/olake-config

services:
  olake-ui:
    environment: *olakeEnv
    volumes:
      - *olakeData
  temporal-worker:
    environment: *olakeEnv
    volumes:
      - *olakeData
```

## Task logs in S3

By default task files stay in the data folder.
`OLAKE_STORAGE_MODE: s3` writes them to an S3 bucket instead.
The worker refuses S3 mode for a driver older than v0.12.0.
Add to `x-olake-env`, with the credentials in `.env`:

```yaml
x-olake-env: &olakeEnv
  OLAKE_STORAGE_MODE: s3
  OLAKE_S3_BUCKET: <bucket>
  OLAKE_S3_REGION: <region>
  OLAKE_S3_PREFIX: <prefix>              # optional key prefix
  OLAKE_S3_ENDPOINT: <url>               # only for S3-compatible stores (MinIO, GCS S3 API)
  OLAKE_S3_ACCESS_KEY_ID: ${OLAKE_S3_ACCESS_KEY_ID}
  OLAKE_S3_SECRET_ACCESS_KEY: ${OLAKE_S3_SECRET_ACCESS_KEY}
```

## Certificates and keys for drivers

For `temporal-worker` only.
A driver that needs a custom CA or a client key reads it from a host folder mounted into each driver container.
`OLAKE_JOB_BIND_MOUNTS` takes comma-separated `<host path>:<container path>` pairs, both absolute:

```yaml
services:
  temporal-worker:
    environment:
      <<: *olakeEnv
      OLAKE_JOB_BIND_MOUNTS: "/home/me/olake/certs:/etc/ssl/custom-certs,/home/me/olake/client-keys:/etc/ssl/client-keys"
```

The source or destination config then names the container path.

## Custom CA for the UI

For `olake-ui` only.
Behind a TLS-inspecting proxy, `olake-ui` needs the proxy's CA to reach registries and other HTTPS endpoints.
The file must exist before the start, or Docker mounts an empty folder in its place:

```yaml
services:
  olake-ui:
    volumes:
      - ./custom-ca.crt:/etc/ssl/certs/custom-ca.crt:ro
```

## Private registry

`CONTAINER_REGISTRY_BASE` replaces `docker.io` in every image name, and tells the UI and the worker where to list and pull driver images.
Put it in `.env`, so compose uses it in the image names too; the compose file already passes it to both services:

```bash
CONTAINER_REGISTRY_BASE=registry.example.com
```

Write the pinned images of step 3 as `${CONTAINER_REGISTRY_BASE:-docker.io}/olakego/ui:<ui-tag>` and `${CONTAINER_REGISTRY_BASE:-docker.io}/olakego/ui-worker:<worker-tag>`.
For a registry that needs a login, add to `x-olake-env`, with the values in `.env`:

```yaml
x-olake-env: &olakeEnv
  CONTAINER_REGISTRY_USERNAME: ${CONTAINER_REGISTRY_USERNAME}
  CONTAINER_REGISTRY_PASSWORD: ${CONTAINER_REGISTRY_PASSWORD}
```

## Usage stats

Add to `x-olake-env`:

```yaml
x-olake-env: &olakeEnv
  TELEMETRY_DISABLED: "true"
```

## Another host port

For `olake-ui` only.
A plain `ports` entry in the override adds a port instead of replacing 8000; `!override` replaces it (Compose 2.24 or later):

```yaml
services:
  olake-ui:
    ports: !override
      - "8080:8000"
```

## Temporal UI

Add `--profile debug` to the start command; the Temporal UI is then on `http://localhost:8081`.

## Check the result

`docker compose -f docker-compose-v1.yml -f compose.override.yml config` prints the merged file without starting anything.
Check that each setting shows under both services where it should, before the start.
