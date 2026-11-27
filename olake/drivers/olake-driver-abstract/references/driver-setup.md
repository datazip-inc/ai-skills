# Driver setup

Each driver will get its own skill (`olake-driver-<source>`). Until it is written, use the connector
pages on olake.io for the `source.json` fields, source prerequisites and cloud variants.

| Driver | Image | Connector docs | CDC needs |
| --- | --- | --- | --- |
| `postgres` | `olakego/source-postgres` | [Postgres](https://olake.io/docs/connectors/postgres) | `wal_level=logical`, a replication slot, a publication, a user with `REPLICATION`. Setup per host (local, RDS, Aurora, Azure, GCP): [setup pages](https://olake.io/docs/connectors/postgres) |
| `mysql` | `olakego/source-mysql` | [MySQL](https://olake.io/docs/connectors/mysql) | `binlog_format=ROW`, `binlog_row_image=FULL`, binlog retention, `REPLICATION SLAVE` and `REPLICATION CLIENT` grants |
| `mongodb` | `olakego/source-mongodb` | [MongoDB](https://olake.io/docs/connectors/mongodb) | Replica set or sharded cluster (change streams), enough oplog retention |
| `mssql` | `olakego/source-mssql` | [SQL Server](https://olake.io/docs/connectors/mssql) | CDC enabled on the database and each table, SQL Server Agent running |
| `oracle` | `olakego/source-oracle` | [Oracle](https://olake.io/docs/connectors/oracle) | No CDC: use `full_refresh` or `incremental` |
| `db2` | `olakego/source-db2` | [DB2](https://olake.io/docs/connectors/db2) | No CDC: use `full_refresh` or `incremental` |
| `s3` | `olakego/source-s3` | [S3](https://olake.io/docs/connectors/s3) | No CDC: `incremental` picks up new or changed files |
| `kafka` | `olakego/source-kafka` | [Kafka](https://olake.io/docs/connectors/kafka) | Brokers reachable, consumer group; `strict_cdc` only |

Get the exact `source.json` fields from the image itself:

```bash
docker run --rm olakego/source-<source>:<tag> spec
```

`spec` prints the JSON schema of `source.json`: required fields, types, defaults. Build `source.json`
from it, with `<PASSWORD>` placeholders.
