# Compatibility matrix (v1)

v1 lists only the combination these skills are verified for. It grows as driver and destination skills
are completed.

| Source | Sync modes | Destination | Catalog | Storage | Run mode | Skills |
| --- | --- | --- | --- | --- | --- | --- |
| Postgres | `full_refresh`, `incremental`, `cdc`, `strict_cdc` | Iceberg | REST | MinIO | CLI, UI (compose) | `olake-driver-postgres`, `olake-destination-iceberg` |

Other sources (MySQL, MongoDB, MSSQL, Oracle, DB2, S3, Kafka) and destinations (Iceberg on Glue, Hive,
JDBC, S3 Tables, Polaris, Unity; Parquet) work in OLake but have no skill yet. For them, run the base
steps in `SKILL.md` and use the connector and writer pages on https://olake.io/docs.
