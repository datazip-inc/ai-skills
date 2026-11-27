# Nessie

`"catalog_type": "nessie"`: Nessie's Iceberg REST endpoint; OLake sends it as `rest`.
Docs: [REST → Nessie](https://olake.io/docs/writers/iceberg/catalog/rest?rest-catalog=nessie).

```json
{
  "type": "ICEBERG",
  "writer": {
    "catalog_type": "nessie",
    "rest_catalog_url": "http://<NESSIE_HOST>:19120/iceberg/",
    "iceberg_s3_path": "s3://<BUCKET>",
    "rest_auth_type": "None",
    "aws_region": "<REGION>",
    "s3_endpoint": "http://<MINIO_HOST>:9000",
    "aws_access_key": "<ACCESS_KEY>",
    "aws_secret_key": "<SECRET_KEY>"
  }
}
```

- `rest_catalog_url` is `<nessie>/iceberg/` (the REST endpoint, not `/api/v2`). A branch other than
  `main`: `/iceberg/<branch>/`.
- Nessie needs its own warehouse config pointing at the same bucket (`nessie.catalog.warehouses.*`).
- Auth: `None`, `Token` (`token`), or `OAuth2` (`oauth2_uri`, `credential`, `scope`).
