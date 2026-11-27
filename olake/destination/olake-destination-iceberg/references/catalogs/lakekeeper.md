# Lakekeeper

`"catalog_type": "lakekeeper"`: a REST catalog; OLake sends it as `rest`.
Docs: [REST → Lakekeeper](https://olake.io/docs/writers/iceberg/catalog/rest?rest-catalog=lakekeeper).

```json
{
  "type": "ICEBERG",
  "writer": {
    "catalog_type": "lakekeeper",
    "rest_catalog_url": "http://<LAKEKEEPER_HOST>:8181/catalog",
    "iceberg_s3_path": "<WAREHOUSE_NAME>",
    "rest_auth_type": "None",
    "aws_region": "<REGION>",
    "s3_endpoint": "http://<MINIO_HOST>:9000",
    "aws_access_key": "<ACCESS_KEY>",
    "aws_secret_key": "<SECRET_KEY>"
  }
}
```

- `rest_catalog_url` ends in `/catalog`.
- `iceberg_s3_path` is the Lakekeeper **warehouse name**, not an `s3://` path. Create the warehouse
  (storage profile) in Lakekeeper first.
- Auth: `rest_auth_type` `None`, `Token` (`token`), or `OAuth2` (`oauth2_uri`, `credential`
  `<client_id>:<client_secret>`, `scope`).
- Storage keys can stay empty when the warehouse vends credentials (Azure ADLS, S3 with STS):
  [../storage/azure.md](../storage/azure.md).
