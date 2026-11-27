# Hive Metastore catalog

`"catalog_type": "hive"`. Metadata in a Hive Metastore (Thrift), data in S3, MinIO or GCS.
Docs: [Hive catalog](https://olake.io/docs/writers/iceberg/catalog/hive).

```json
{
  "type": "ICEBERG",
  "writer": {
    "catalog_type": "hive",
    "hive_uri": "thrift://<METASTORE_HOST>:9083",
    "hive_clients": 5,
    "hive_sasl_enabled": false,
    "iceberg_s3_path": "s3a://<BUCKET>/<PATH>",
    "aws_region": "us-east-1",
    "aws_access_key": "<ACCESS_KEY>",
    "aws_secret_key": "<SECRET_KEY>",
    "s3_endpoint": "http://<MINIO_HOST>:9000",
    "s3_path_style": true,
    "s3_use_ssl": false
  }
}
```

- `hive_uri` and `hive_clients` are required. `hive_clients` is the Thrift connection pool size (5–10).
- The metastore itself must reach the same storage: its `fs.s3a.*` settings point at the same bucket
  and endpoint.
- `hive_sasl_enabled: true` only when the metastore enforces SASL (Kerberos).
- GCP Dataproc Metastore: `iceberg_s3_path` is `gs://<bucket>/<path>`, no S3 keys or endpoint; the
  container needs Google credentials for GCS ([../storage/gcs.md](../storage/gcs.md)).

## Errors

| Error | Fix |
| --- | --- |
| `hive_uri is required when using Hive catalog` | Set `hive_uri`. |
| `TTransportException` / `connection refused` on 9083 | Metastore down or not reachable from the container. |
| `No FileSystem for scheme` in metastore logs | The metastore lacks the S3A or GCS jars or config. |
| `Location does not exist: s3a://.../metadata/00000-<uuid>.metadata.json` (`NoSuchKeyException`), after `UNIQUE_DATABASE` in an earlier line | First sync with several streams raced on namespace creation and left a table whose metadata file is missing. Seen once in two runs on v1.1.2. | Drop that table in the metastore, then rerun. To avoid it, sync one stream first, then add the rest. |

## Local metastore on MinIO

Tested with `apache/hive:4.0.0` (embedded Derby) on the POC network. The image ships the S3A jars in
`/opt/hadoop/share/hadoop/tools/lib`, off the classpath by default.

```bash
docker run -d --name hive-metastore --network olake-poc \
  -e SERVICE_NAME=metastore \
  -e HADOOP_CLASSPATH='/opt/hadoop/share/hadoop/tools/lib/*' \
  -v "$PWD/core-site.xml:/opt/hadoop/etc/hadoop/core-site.xml:ro" \
  apache/hive:4.0.0
```

`core-site.xml` sets `fs.s3a.endpoint` (`http://minio:9000`), `fs.s3a.access.key`,
`fs.s3a.secret.key`, `fs.s3a.path.style.access` (`true`) and `fs.s3a.connection.ssl.enabled`
(`false`). Then `hive_uri` is `thrift://hive-metastore:9083`. Embedded Derby is for tests only; use a
Postgres or MySQL backed metastore for real loads.
