---
name: olake-destination-iceberg
description: "Write OLake syncs to Apache Iceberg: destination.json, a local REST catalog + MinIO stack for a POC, where the tables land, and a check through the REST API. Use when the destination is Iceberg, the user needs a local Iceberg setup, or asks where the synced tables are."
metadata:
  parent: olake-destination-abstract
  status: experimental
---

# Iceberg destination

`"type": "ICEBERG"` in `destination.json`. Every source image writes it; nothing extra to install.
This skill covers the REST catalog on MinIO or S3. How OLake writes (columns, upserts, deletes,
partitioning) is in `olake-destination-abstract`. The run is in `olake-protocol`.

## When to use

- The destination is Iceberg with a REST catalog, on MinIO or S3.
- The user has no Iceberg setup and wants a local one for a POC.
- `check --destination` fails, or the user cannot find the synced tables.
- Other catalogs (Glue, Hive, JDBC, Polaris, Lakekeeper, Nessie, Unity, S3 Tables, BigLake): fields in
  [references/config.md](references/config.md) and the
  [Iceberg catalog docs](https://olake.io/docs/writers/iceberg/catalog/overview).

## Inputs to collect

Ask only for what is missing. Never echo a key back.

| Input | Example | Where it comes from |
| --- | --- | --- |
| Existing catalog, or local POC stack? | existing / local | User |
| `rest_catalog_url` | `http://iceberg-rest:8181` | User, or the local stack |
| `iceberg_s3_path` | `s3://warehouse/olake` | User. Bucket must exist. |
| `s3_endpoint` | `http://minio:9000` | MinIO only. Leave out for AWS S3. |
| `aws_region`, `aws_access_key`, `aws_secret_key` | `us-east-1`, `<ACCESS_KEY>`, `<SECRET_KEY>` | User. On AWS, leave keys out to use the instance role. |
| Catalog auth | none, bearer `token`, OAuth2 | User. Fields: [references/catalogs/rest.md](references/catalogs/rest.md). |

## Prerequisites

- [ ] The catalog and the storage are reachable from the OLake container. Same Docker network: use
      service names. On the host: `host.docker.internal`.
- [ ] The keys can list, read and write `iceberg_s3_path`, and the catalog lets them create namespaces
      and tables.

## Steps

1. Local POC only: start the stack in [assets/rest-minio/](assets/rest-minio/docker-compose.yml).
   ```bash
   docker compose -f assets/rest-minio/docker-compose.yml up -d
   curl -s http://localhost:8181/v1/config     # {"defaults":{},"overrides":{}}
   ```
   Port taken: `MINIO_PORT=19000 MINIO_CONSOLE_PORT=19001 REST_PORT=18181 docker compose ... up -d`,
   then use `18181` in the curl and verify commands. Run every OLake command with `--network olake-poc`.
   If the source database runs in Docker too, attach it: `docker network connect olake-poc <container>`.
2. Write `destination.json`. For the local stack:
   ```json
   {
     "type": "ICEBERG",
     "writer": {
       "catalog_type": "rest",
       "rest_catalog_url": "http://iceberg-rest:8181",
       "iceberg_s3_path": "s3://warehouse/olake",
       "iceberg_db": "olake",
       "s3_endpoint": "http://minio:9000",
       "s3_path_style": true,
       "s3_use_ssl": false,
       "aws_region": "us-east-1",
       "aws_access_key": "admin",
       "aws_secret_key": "password"
     }
   }
   ```
   `admin` / `password` are the local stack's fixed keys. For any other setup use the user's values and
   `<ACCESS_KEY>` / `<SECRET_KEY>` placeholders. AWS S3: drop `s3_endpoint`, `s3_path_style`, `s3_use_ssl`.
   Storage notes: [references/storage/minio.md](references/storage/minio.md).
3. `check --destination` (`olake-protocol` step 2). It creates a `test_olake` namespace and table.
4. Discover and sync (`olake-protocol`).

## Where the tables land

- Namespace: `destination_database` from `discover`, reformatted: `<source>_<database>_<schema>`,
  for example `postgres_shop_public`. `iceberg_db` is used only when `destination_database` is empty.
- Table: the source table name, lower-cased, non `a-z 0-9` characters as `_`.
- Extra columns: `_olake_id`, `_olake_timestamp`, `_op_type`, and with CDC `_cdc_timestamp` plus a
  source position column (`_cdc_lsn` on Postgres).

## Verify

```bash
python3 scripts/verify_iceberg.py http://localhost:8181                        # namespaces
python3 scripts/verify_iceberg.py http://localhost:8181 postgres_shop_public    # tables and counts
```

- The table is listed, and `records` equals the source row count after the first sync.
- After a CDC change and a rerun with `--state`, `records` grows by the changed rows.
- With deletes or upserts, `records` counts rows before deletes: compare with a query engine
  (`SELECT COUNT(*) FROM <catalog>.<namespace>.<table>`).

## Common errors

| Error | Cause | Fix |
| --- | --- | --- |
| `rest_catalog_url is required when using REST catalog` | Missing field | Set `rest_catalog_url`. |
| `connection refused` / `UnknownHostException` to the catalog or MinIO | Wrong host from inside the container | Service names with `--network olake-poc`; `host.docker.internal` for host services. |
| `NoSuchBucket` | Bucket in `iceberg_s3_path` missing | Create it (local stack: `mc` creates `warehouse`). |
| `Bind for 0.0.0.0:9000 failed: port is already allocated` | Host port taken | Set `MINIO_PORT`, `MINIO_CONSOLE_PORT`, `REST_PORT` (step 1). |

Writer errors (Java, gRPC, permissions): `olake-destination-abstract`.

## Next

- Upserts, delete formats, partitioning: `olake-destination-abstract`.
- Every field: [references/config.md](references/config.md).

## Rules

- The local stack is for a POC only: fixed keys, a public network name, no TLS.
- `docker compose down -v` deletes the catalog and every synced table: confirm with the user first.
- Never print the user's keys or tokens; use placeholders.
