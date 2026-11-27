# AWS Glue catalog

`"catalog_type": "glue"` (also the default when `catalog_type` is missing). Data in S3, metadata in
Glue. Docs: [Glue catalog](https://olake.io/docs/writers/iceberg/catalog/glue).

```json
{
  "type": "ICEBERG",
  "writer": {
    "catalog_type": "glue",
    "iceberg_s3_path": "s3://<BUCKET_NAME>/<PATH>",
    "aws_region": "<AWS_REGION>",
    "aws_access_key": "<ACCESS_KEY>",
    "aws_secret_key": "<SECRET_KEY>"
  }
}
```

- Leave out the keys to use the instance role, `AWS_*` environment variables or `aws_profile`.
- The catalog name is always `olake_iceberg`; `catalog_name` is not used for Glue.
- Bucket and Glue in the same region.
- Separate Glue credentials, endpoint, region or account: `"glue_additional_config": true` plus
  `glue_access_key`, `glue_secret_key`, `glue_endpoint`, `glue_region`, `glue_catalog_id`.

## IAM

The role or user needs:

| Service | Actions | Resources |
| --- | --- | --- |
| Glue | `CreateDatabase`, `GetDatabase`, `GetDatabases`, `UpdateDatabase`, `CreateTable`, `GetTable`, `GetTables`, `UpdateTable` (optional `SearchTables`, `DeleteTable` for `clear-destination`) | `catalog`, `database/<db>`, `table/<db>/*` |
| S3 | `ListBucket`, `GetBucket*`, `GetObject`, `PutObject`, `DeleteObject` | the bucket and `bucket/*` |
| S3 | `ListAllMyBuckets` | `*` |

Databases already created: `CreateDatabase` can be dropped. Lake Formation in front of Glue also needs
grants on the database there.

## Query

Athena: `SELECT * FROM "<namespace>"."<table>" LIMIT 10;`

## Errors

| Error | Fix |
| --- | --- |
| `AccessDeniedException ... not authorized to perform: glue:<action>` | Add the action to the policy. |
| `Region must be specified` | Set `aws_region`. |
| Lake Formation `Insufficient Lake Formation permission(s)` | Grant the principal create and alter on the database in Lake Formation. |
