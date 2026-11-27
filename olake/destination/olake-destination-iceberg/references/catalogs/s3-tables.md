# Amazon S3 Tables

`"catalog_type": "s3tables"`. OLake sends it as `rest` and turns on SigV4 signing with signing name
`s3tables`. Docs: [REST → S3 Tables](https://olake.io/docs/writers/iceberg/catalog/rest?rest-catalog=s3-tables).

```json
{
  "type": "ICEBERG",
  "writer": {
    "catalog_type": "s3tables",
    "rest_catalog_url": "https://s3tables.<REGION>.amazonaws.com/iceberg",
    "iceberg_s3_path": "arn:aws:s3tables:<REGION>:<ACCOUNT_ID>:bucket/<TABLE_BUCKET>",
    "rest_auth_type": "sigv4",
    "rest_signing_region": "<REGION>",
    "aws_region": "<REGION>",
    "aws_access_key": "<ACCESS_KEY>",
    "aws_secret_key": "<SECRET_KEY>"
  }
}
```

- `iceberg_s3_path` is the table bucket **ARN**.
- IAM: `s3tables:*` on the table bucket and `arn:...:bucket/<TABLE_BUCKET>/table/*` (at least
  `CreateNamespace`, `GetNamespace`, `ListNamespaces`, `CreateTable`, `GetTable`, `ListTables`,
  `GetTableMetadataLocation`, `UpdateTableMetadataLocation`, `PutTableData`, `GetTableData`).
- Namespace and table names: lowercase letters, numbers and `_` only.
- Query: Athena or EMR through the `s3tablescatalog` integration.
