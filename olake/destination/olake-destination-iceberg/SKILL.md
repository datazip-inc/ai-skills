---
name: olake-destination-iceberg
description: "Write OLake syncs to Apache Iceberg on any catalog (REST, Glue, Hive, JDBC, Lakekeeper, Nessie, Polaris, Unity, S3 Tables, BigLake, Horizon) and S3, MinIO, GCS or ADLS, plus a local POC stack with Trino. Use when the destination is Iceberg, or to find or query the synced tables."
metadata:
  parent: olake-destination-abstract
  status: experimental
---

# Iceberg destination

`"type": "ICEBERG"` in `destination.json`. Every source image writes it; nothing extra to install.
How OLake writes (columns, upserts, deletes, partitioning) is in `olake-destination-abstract`. The run
is in `olake-protocol`.

| Catalog | `catalog_type` | Guide |
| --- | --- | --- |
| Generic REST (local POC stack, Tabular, Gravitino) | `rest` | [references/catalogs/rest.md](references/catalogs/rest.md) |
| AWS Glue | `glue` | [references/catalogs/glue.md](references/catalogs/glue.md) |
| Hive Metastore, Dataproc Metastore | `hive` | [references/catalogs/hive.md](references/catalogs/hive.md) |
| JDBC (Postgres, MySQL) | `jdbc` | [references/catalogs/jdbc.md](references/catalogs/jdbc.md) |
| Lakekeeper | `lakekeeper` | [references/catalogs/lakekeeper.md](references/catalogs/lakekeeper.md) |
| Nessie | `nessie` | [references/catalogs/nessie.md](references/catalogs/nessie.md) |
| Apache Polaris, Snowflake Open Catalog | `polaris` | [references/catalogs/polaris.md](references/catalogs/polaris.md) |
| Databricks Unity Catalog | `unity` | [references/catalogs/unity.md](references/catalogs/unity.md) |
| Amazon S3 Tables | `s3tables` | [references/catalogs/s3-tables.md](references/catalogs/s3-tables.md) |
| Google BigLake metastore | `biglake` | [references/catalogs/biglake.md](references/catalogs/biglake.md) |
| Snowflake Horizon | `horizon` | [references/catalogs/horizon.md](references/catalogs/horizon.md) |

Storage: [S3](references/storage/s3.md), [MinIO](references/storage/minio.md),
[GCS](references/storage/gcs.md), [Azure ADLS Gen2](references/storage/azure.md).

## When to use

- The destination is Iceberg, with any catalog in the table above.
- The user has no Iceberg setup and wants a local one for a POC: use the REST + MinIO stack.
- `check --destination` fails, or the user cannot find or query the synced tables.

## Inputs to collect

Ask only for what is missing. Never echo a key back.

| Input | Example | Where it comes from |
| --- | --- | --- |
| Existing catalog, or local POC stack? | existing / local | User. Existing: which catalog (table above). |
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
   To query the tables later, add Trino: `--profile query` on the same `up -d` (2 GB memory).
2. Write `destination.json`. Existing catalog: take the example from its guide. For the local stack:
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

- Namespace: `destination_database` from `discover`, reformatted: `<source>_<database>_<schema>`.
  `iceberg_db` is used only when `destination_database` is empty. Seen on v1.1.2:

  | Source | Namespace |
  | --- | --- |
  | Postgres `shop`, schema `public` | `postgres_shop_public` |
  | MySQL `shop` | `mysql_shop` |
  | MongoDB `shop` | `mongodb_shop` |
  | MSSQL `shop`, schema `dbo` | `mssql_shop_dbo` |
  | Oracle, owner `OLAKE` | `oracle_olake` |
  | Db2 `SHOP`, schema `DB2INST1` | `db2_shop_db2inst1` |
  | S3 bucket `src` | `s3_src_s3` |
  | Kafka | `kafka_topics` |

  Nessie lists the tables under the branch prefix `main`.
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
- With deletes or upserts, `records` counts rows before deletes. Count live rows with an engine:
  `WHERE _op_type <> 'd'`. Local stack: start the bundled Trino with `--profile query`
  ([references/query-engines.md](references/query-engines.md)).
- Glue and other non-REST catalogs: query with an engine; the script reads REST catalogs only.

## Common errors

| Error | Cause | Fix |
| --- | --- | --- |
| `rest_catalog_url is required when using REST catalog` | Missing field | Set `rest_catalog_url`. |
| `connection refused` / `UnknownHostException` to the catalog or MinIO | Wrong host from inside the container | Service names with `--network olake-poc`; `host.docker.internal` for host services. |
| `NoSuchBucket` | Bucket in `iceberg_s3_path` missing | Create it (local stack: `mc` creates `warehouse`). |
| `Bind for 0.0.0.0:9000 failed: port is already allocated` | Host port taken | Set `MINIO_PORT`, `MINIO_CONSOLE_PORT`, `REST_PORT`, `TRINO_PORT` (step 1). |
| First sync with several streams: `ERROR` with `duplicate key ... iceberg_namespace_properties_pkey` or `Failed to execute: INSERT INTO iceberg_namespace_properties`, then `retrying after 60.00 seconds` | Streams create the same namespace at once | None: the retry succeeds and the sync completes. |
| MongoDB, S3 or Kafka table has one column `data` | `normalization` is `false` by default for them | Set `"normalization": true` on the stream, `clear-destination`, sync. |

Writer errors (Java, gRPC, permissions): `olake-destination-abstract`.

## Next

- Upserts, delete formats, partitioning: `olake-destination-abstract`.
- Query the tables: [references/query-engines.md](references/query-engines.md).
- Every field: [references/config.md](references/config.md).

## Rules

- The local stack is for a POC only: fixed keys, a public network name, no TLS.
- `docker compose down -v` deletes the catalog and every synced table: confirm with the user first.
- Never print the user's keys or tokens; use placeholders.
