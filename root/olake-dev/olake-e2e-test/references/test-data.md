# Test source and destination

The local test source (a database for the driver under test) and the local Iceberg destination (MinIO, JDBC catalog, Spark) run in Docker on the host, for both docker compose and Kubernetes stacks.
Driver containers and pods reach them through ports published on the host.

## Contents

- 1. Sources: one local stack per driver
- 2. Start, check Spark, seed
- 3. Connection values
- 4. Verify with Spark, and the source dump
- 5. Handoff rows
- 6. Teardown

## 1. Sources: one local stack per driver

The olake repo has a local stack for each driver with a `drivers/<driver>/docker-compose.yml`; `make -C <olake> olake.<driver>.start` starts it and waits until it answers.
The source is the driver the change touches, else `postgres`.

| Driver | Container | Host port | Login | Client, for seeding and dumps |
| --- | --- | --- | --- | --- |
| `postgres` | `olake_postgres-test` | 5433 | `postgres` / `secret1234`, database `postgres`; logical replication on | `docker exec -i olake_postgres-test psql -U postgres -d postgres -v ON_ERROR_STOP=1` |
| `mysql` | `olake_mysql-test` | 3306 | `mysql` / `secret1234`, database `olake_mysql_test`; root `root1234` | `docker exec -i olake_mysql-test mysql -u root -proot1234 olake_mysql_test` |
| `mongodb` | `primary_mongo` | 27017 | `mongodb` / `secure_password123`, auth database `admin`, database `olake_mongodb_test`; replica set `rs0` | `docker exec -i primary_mongo mongosh -u mongodb -p secure_password123 --authenticationDatabase admin olake_mongodb_test` |
| `mssql` | `olake-mssql` | 1433 | `sa` / `Password!123` | `docker exec -i olake-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password!123' -C` |
| `oracle` | `oracle-23c` | 1521 | `system` / `secret1234`, service `ORCL` | `docker exec -i oracle-23c sqlplus -s system/secret1234@//localhost:1521/ORCL` |
| `db2` | `db2-test` | 50000 | `db2inst1` / `secret1234`, database `TESTDB` | `docker cp` the seed into the container, then `docker exec db2-test su - db2inst1 -c 'db2 connect to TESTDB && db2 -tvf /tmp/seed.sql'` |
| `kafka` | `kafkaJson`, `kafkaAvro`, `schema-registry` | 29092 (JSON), 39092 (Avro), 8081 (schema registry) | none | `docker exec -i kafkaJson kafka-console-producer --bootstrap-server localhost:9092 --topic <topic>` |
| `s3` | `minio`, from the destination stack | 9000 | `admin` / `password` | `olake.s3.start` starts only MinIO; see `<olake>/drivers/s3/README.md` for the test files |

- Read from each driver's `docker-compose.yml` and `driver.mk` on 2026-11-19; only `postgres` has been run end to end with this skill.
  When a value here and the driver's files disagree, the files win: the `PROBE.<driver>` line in `drivers/<driver>/driver.mk` is a working client command.
- `mssql` and `db2` images are `linux/amd64`: on an ARM Mac they run emulated and start slowly (db2 waits up to about 12 minutes).
  Start them first, in the background.
- `kafka`'s schema registry takes port 8081, the Temporal UI port of a compose stack started with `--profile debug`: do not use both.
- `mongodb` announces its replica set member as `host.docker.internal:27017`, so clients outside Docker Desktop need that name to resolve.

## 2. Start, check Spark, seed

```bash
make -C <olake> olake.<driver>.start
make -C <olake> olake.destination.all.start
```

The source projects are named after the driver's folder (`postgres`, `mysql`, ...) and the destination project is `local-test`; their teardown targets delete those projects' volumes and data folder.
When the preflight record already lists one of these projects, the user started it: ask before reusing it, and never run its teardown target.
Before the first start, record whether `<olake>/destination/iceberg/local-test/data` exists: the destination keeps its MinIO and catalog data there, across stacks.
Then check Spark with a real query:

```bash
docker exec spark-iceberg /opt/spark/bin/spark-sql -e "SHOW NAMESPACES IN olake_iceberg"
```

If it fails on the first boot (a jar download race), run `docker restart spark-iceberg` and query again.

Write the seed to `<test-dir>/seed.<ext>` (for SQL sources one `INSERT` per row, ending with a row count) and pipe it into the driver's client, for example:

```bash
docker exec -i olake_postgres-test psql -U postgres -d postgres -v ON_ERROR_STOP=1 < <test-dir>/seed.sql
```

## 3. Connection values

| Setting | Value |
| --- | --- |
| Source host, port | `host.docker.internal`, the host port of the driver in section 1 |
| Source login | The login of the driver in section 1 |
| Catalog | JDBC, `jdbc:postgresql://host.docker.internal:5432/iceberg`, user `iceberg`, password `password` |
| Storage | `http://host.docker.internal:9000`, path style, no SSL, access key `admin`, secret `password`, region `us-east-1` |
| Warehouse path | `s3a://warehouse` |
| Catalog name | `olake_iceberg` (the spec default, and the catalog Spark is configured with) |

Destination ports on the host: 5432 (catalog Postgres), 9000 and 9001 (MinIO API and console), 15002 (Spark Connect), 8088 (Spark UI).
The same values work from compose driver containers and from kind pods on Docker Desktop (checked on 2026-11-19 with kind v0.31).
Map the values to the key names in the spec of the version under test.
Do not copy configs from the olake repo's test data: they carry keys the current spec no longer has (for example `iceberg_db`).

On Linux, `host.docker.internal` does not resolve inside containers by default.
Use the bridge gateway instead: `docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}'`.

## 4. Verify with Spark

```bash
docker exec spark-iceberg /opt/spark/bin/spark-sql -e "SHOW TABLES IN olake_iceberg.<namespace>; DESCRIBE olake_iceberg.<namespace>.<table>; SELECT * FROM olake_iceberg.<namespace>.<table> ORDER BY 1"
```

Put every query of one verify pass in one call: each call starts a JVM, about 10 seconds.
Add `--conf spark.sql.session.timeZone=UTC` so timestamps print in UTC.
`<namespace>` is the stream's `destination_database` from discover with `:` replaced by `_` (for example `orch_baseline_postgres:public` becomes `orch_baseline_postgres_public`).

Dump the source for the comparison with NULL printed as `NULL`, not as an empty string; for postgres:

```bash
docker exec olake_postgres-test psql -U postgres -d postgres -At -F $'\t' -P null=NULL \
  -c "SET timezone='UTC'; SELECT <columns> FROM <table> ORDER BY 1" > <test-dir>/source-dump.tsv
```

## 5. Handoff rows

| What | Value |
| --- | --- |
| Test source | From the host: `localhost:<port>`. In the OLake UI: host `host.docker.internal`, the port and login of the driver in section 1 |
| Iceberg destination | The values in section 3, entered in the UI form for a JDBC catalog |
| MinIO console | `http://localhost:9001`, `admin` / `password` |
| Spark | `docker exec -it spark-iceberg /opt/spark/bin/spark-sql`, catalog `olake_iceberg`; Spark UI `http://localhost:8088` |

## 6. Teardown

The teardown targets delete the volumes, and `olake.destination.all.teardown` also deletes `<olake>/destination/iceberg/local-test/data`.
When that folder existed before the stack started, it can hold the user's own data: stop the containers instead, and ask before a teardown.

```bash
make -C <olake> olake.<driver>.teardown          # or olake.<driver>.stop
make -C <olake> olake.destination.all.teardown   # or olake.destination.all.stop, when the data folder was there before
```
