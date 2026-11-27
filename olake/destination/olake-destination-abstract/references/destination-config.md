# `destination.json`

Same shape for both writers: `type` plus a `writer` object.

```json
{
  "type": "ICEBERG",
  "writer": { "...": "..." }
}
```

`type` is `ICEBERG` or `PARQUET`. Get every field, with types and defaults, from the image:

```bash
docker run --rm olakego/source-<source>:<tag> spec --destination-type iceberg
docker run --rm olakego/source-<source>:<tag> spec --destination-type parquet
```

## Iceberg: the fields that matter first

| Field | Example | Notes |
| --- | --- | --- |
| `catalog_type` | `rest`, `glue`, `hive`, `jdbc` | Missing means `glue`. |
| `iceberg_s3_path` | `s3://warehouse/olake` | Warehouse location. |
| `iceberg_db` | `olake` | Default namespace for tables. |
| `rest_catalog_url` | `http://host.docker.internal:8181/catalog` | REST only. |
| `jdbc_url`, `jdbc_username`, `jdbc_password` | | JDBC only. |
| `hive_uri` | `thrift://hive:9083` | Hive only. |
| `aws_region`, `aws_access_key`, `aws_secret_key` | | S3 and Glue. Leave keys out to use the instance role. |
| `s3_endpoint`, `s3_path_style`, `s3_use_ssl` | `http://host.docker.internal:9000`, `true`, `false` | MinIO and other S3-compatible storage. |

Catalog by catalog (REST variants: Polaris, Lakekeeper, Unity, S3 Tables, Nessie, Horizon, BigLake):
`olake-destination-iceberg`, or the [Iceberg catalog docs](https://olake.io/docs/writers/iceberg/catalog/overview).

## Parquet: the fields that matter first

| Field | Example | Notes |
| --- | --- | --- |
| `local_path` | `/mnt/config/output` | Local disk. Use a path under `/mnt/config` so files land on the host. |
| `s3_bucket`, `s3_path`, `s3_region` | `my-bucket`, `/olake`, `us-east-1` | S3. |
| `s3_access_key`, `s3_secret_key`, `s3_endpoint` | | Keys; endpoint for MinIO or S3-compatible storage. |
| `azure_storage_account_name`, `azure_container_name`, `azure_path`, `azure_auth_type` | | Azure Blob / ADLS. |
| `max_file_size_mb` | `512` | Roll over to a new file at this size. |

Parquet writes files only: no upserts, no deletes. Every change is a new row. Guides:
[Parquet writer docs](https://olake.io/docs/writers/parquet/config).
