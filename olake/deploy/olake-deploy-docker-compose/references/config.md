# Compose file settings

Every setting lives in the downloaded `docker-compose.yml`
([`docker-compose-v1.yml` at v0.9.3](https://github.com/datazip-inc/olake-ui/blob/v0.9.3/docker-compose-v1.yml)).
Edit the file, then `docker compose up -d` to apply. Most settings are YAML anchors at the top of the
file; `x-envs.shared` is injected into `olake-ui` and `temporal-worker`.

## Admin user

```yaml
x-signup-defaults:
  username: &defaultUsername "<ADMIN_USER>"
  password: &defaultPassword "<ADMIN_PASSWORD>"
  email: &defaultEmail "<ADMIN_EMAIL>"
```

`signup-init` creates this user on start. If the user exists, it gets HTTP 409 and exits 1: an edit
after the first start does not change the password of the existing user.

## Encryption key

`OLAKE_SECRET_KEY` encrypts source and destination configs stored in Postgres.

```yaml
x-encryption:
  key: &encryptionKey "<PASSPHRASE>"           # any string, hashed with SHA-256
  # key: &encryptionKey "arn:aws:kms:<REGION>:<ACCOUNT>:key/<KEY_ID>"   # AWS KMS
  # key: &encryptionKey ""                      # no encryption (default)
```

Set it before the first config is saved. Configs saved under one key cannot be read with another.

## Data directory

```yaml
x-app-defaults:
  host_persistence_path: &hostPersistencePath /custom/path/to/olake-data
```

Default `${PWD}/olake-data`. The worker passes this host path to driver containers, so it must be a
real path on the Docker host. Contents: [volumes.md](volumes.md).

## Shared environment (`x-envs.shared`)

| Variable | Default | Purpose |
| --- | --- | --- |
| `CONTAINER_REGISTRY_BASE` | `${CONTAINER_REGISTRY_BASE:-docker.io}` | Registry prefix for every image, including driver images. |
| `OLAKE_SECRET_KEY` | `*encryptionKey` | See above. |
| `PERSISTENT_DIR` | `*hostPersistencePath` | Host path of the data directory. |
| `ENABLE_OPTIMIZATION` | `false` | Fusion compaction. Needs the `fusion` profile. |

Add variables here to pass them to both services.

## Private registry

Log in first (`docker login <REGISTRY>`), then:

```yaml
x-envs:
  shared: &sharedEnvs
    CONTAINER_REGISTRY_BASE: "<REGISTRY>"
    CONTAINER_REGISTRY_USERNAME: "<USERNAME>"
    CONTAINER_REGISTRY_PASSWORD: "<PASSWORD>"
    CONTAINER_REGISTRY_INSECURE: "false"
    CONTAINER_REGISTRY_TLS_SKIP_VERIFY: "false"
    # CONTAINER_REGISTRY_CA_CERT: "<PEM>"
```

Mirror every compose image and each `olakego/source-<driver>` image the jobs use. The variable can also
come from a `.env` file next to the compose file.

## External Temporal

```yaml
x-envs:
  shared: &sharedEnvs
    TEMPORAL_EXTERNAL: "true"
    TEMPORAL_ADDRESS: "<region>.<cloud>.api.temporal.io:7233"
    TEMPORAL_API_KEY: "<TEMPORAL_API_KEY>"
    TEMPORAL_NAMESPACE: "<NAMESPACE>"
    TEMPORAL_TASK_QUEUE: "<TASK_QUEUE>"
    TEMPORAL_ENABLE_TLS: "true"
```

The built-in `temporal` service still starts; `olake-ui` and the worker use the external one.

## External Postgres

The [install docs](https://olake.io/docs/install/olake-ui#external-postgresql-configuration) describe an
`x-db-envs` block. The v0.9.3 `docker-compose-v1.yml` has no such block: the Temporal services read
`POSTGRES_SEEDS`, `DB_PORT`, `POSTGRES_USER`, `POSTGRES_PWD`, and the OLake server reads
`OLAKE_POSTGRES_HOST`, `OLAKE_POSTGRES_PORT`, `OLAKE_POSTGRES_USER`, `OLAKE_POSTGRES_PASSWORD`,
`OLAKE_POSTGRES_DBNAME`, `OLAKE_POSTGRES_SSLMODE`. Check the file the user downloaded before editing,
and test on a copy: this path is not verified here. For a TLS Postgres, the file has commented
`SQL_TLS*` lines under `temporal`.

## Retention (on `temporal-worker`)

```yaml
services:
  temporal-worker:
    environment:
      LOG_RETENTION_PERIOD: "30"          # days; default 30. Cleaner runs daily at 00:00 local time.
      TEMPORAL_RETENTION_PERIOD: "168h"   # hours; default 168h (7 days), minimum 1 day.
```

`LOG_RETENTION_PERIOD` deletes whole job log folders older than the period. `TEMPORAL_RETENTION_PERIOD`
limits the run history shown in the UI.

## Files for driver containers (`OLAKE_JOB_BIND_MOUNTS`)

A CA bundle, client key or keytab a source needs goes in through a read-only bind mount. Set it on
`temporal-worker` (the file has it commented):

```yaml
      OLAKE_JOB_BIND_MOUNTS: "${PWD}/olake-certs:/etc/ssl/custom-certs"
```

Format: comma-separated `<absolute host path>:<absolute container path>`. Each target must be unique.
Point the connector config at the container path, for example `server_ca_path` with
`cert_source: "path"`. Do not mount over `/etc/ssl/certs` or inside `/mnt/config`.

## Profiles

| Profile | Adds |
| --- | --- |
| `debug` | `temporal-ui` on `8081`. |
| `fusion` | Fusion (compaction) and its setup containers, ports `1630`, `1260`, `1261`. |

`docker compose --profile debug up -d`. With the piped one-liner:
`... | docker compose -f - --profile debug up -d`.
