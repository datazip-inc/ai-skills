# Query the synced tables

Count rows with an engine when the table has deletes or upserts: the REST check in
`scripts/verify_iceberg.py` counts rows in data files before deletes. Pick an engine that reads the
table's delete format: `olake spec --available-query-engines` and `olake-destination-abstract`.

Names: `<catalog>.<namespace>.<table>`, where namespace is `<source>_<database>_<schema>` by default.

Count live rows only: a CDC delete leaves a row with `_op_type = 'd'`, so `COUNT(*)` includes
deleted keys. Filter them out: `WHERE _op_type <> 'd'`. A CDC update replaces the row.

## Trino on the local POC stack

The POC compose file has Trino under the `query` profile, wired to `iceberg-rest` and `minio`.

```bash
docker compose -f assets/rest-minio/docker-compose.yml --profile query up -d
docker exec -it olake-trino trino --catalog iceberg
```

Trino needs about 2 GB of memory and takes a few seconds to start. Port taken: set `TRINO_PORT`.

```sql
SHOW SCHEMAS;
SHOW TABLES FROM postgres_shop_public;
SELECT COUNT(*) FROM postgres_shop_public.orders WHERE _op_type <> 'd';
SELECT _op_type, COUNT(*) FROM postgres_shop_public.orders GROUP BY _op_type;
```

Streams synced with `normalization: false` (the default for MongoDB, S3 and Kafka) have one JSON
string column `data`:

```sql
SELECT json_extract_scalar(data, '$.status') AS status, COUNT(*)
FROM mongodb_shop.orders WHERE _op_type <> 'd' GROUP BY 1;
```

One-off query without a shell: `docker exec olake-trino trino --catalog iceberg --execute "<SQL>"`.

## Spark SQL (REST catalog on MinIO)

Tested against the POC stack. Each run downloads the Iceberg jars from Maven Central, so it needs
internet access and about a minute to start.

```bash
docker run --rm -it --network olake-poc \
  -e AWS_ACCESS_KEY_ID=admin -e AWS_SECRET_ACCESS_KEY=password -e AWS_REGION=us-east-1 \
  apache/spark:3.5.1 /opt/spark/bin/spark-sql \
  --packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.6.1,org.apache.iceberg:iceberg-aws-bundle:1.6.1 \
  --conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions \
  --conf spark.sql.catalog.olake=org.apache.iceberg.spark.SparkCatalog \
  --conf spark.sql.catalog.olake.type=rest \
  --conf spark.sql.catalog.olake.uri=http://iceberg-rest:8181 \
  --conf spark.sql.catalog.olake.io-impl=org.apache.iceberg.aws.s3.S3FileIO \
  --conf spark.sql.catalog.olake.s3.endpoint=http://minio:9000 \
  --conf spark.sql.catalog.olake.s3.path-style-access=true \
  --conf spark.jars.ivy=/tmp/.ivy
```

```sql
SHOW NAMESPACES IN olake;
SELECT COUNT(*) FROM olake.postgres_shop_public.orders;
SELECT _op_type, COUNT(*) FROM olake.postgres_shop_public.orders GROUP BY _op_type;
```

Other catalogs: `type=glue` (with `warehouse=s3://...`), `type=hive` (`uri=thrift://...`),
`type=jdbc` (`uri=jdbc:...`, `jdbc.user`, `jdbc.password`), or the vendor's REST settings
(`uri`, `warehouse=<warehouse or catalog name>`, `credential`, `token`).

## Trino (your own cluster)

`etc/catalog/olake.properties`:

```properties
connector.name=iceberg
iceberg.catalog.type=rest
iceberg.rest-catalog.uri=http://iceberg-rest:8181
fs.native-s3.enabled=true
s3.endpoint=http://minio:9000
s3.path-style-access=true
s3.region=us-east-1
s3.aws-access-key=admin
s3.aws-secret-key=password
```

`SELECT COUNT(*) FROM olake.postgres_shop_public.orders;`

## Athena (Glue)

`SELECT COUNT(*) FROM "<namespace>"."<table>";` Athena reads `eq` and `pos` deletes, not `dv`.
