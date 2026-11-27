# Parquet storage

`storage_type` is `S3` (default) or `Azure`. With `S3` and no `s3_bucket` / `s3_region`, files stay on
local disk at `local_path`.

## Local

```json
{ "type": "PARQUET", "writer": { "local_path": "/mnt/config/output" } }
```

Use a path under `/mnt/config` so files land in the mounted host folder; any other path is lost when
the container exits.

## S3

```json
{
  "type": "PARQUET",
  "writer": {
    "s3_bucket": "<BUCKET>",
    "s3_region": "<REGION>",
    "s3_path": "/olake",
    "s3_access_key": "<ACCESS_KEY>",
    "s3_secret_key": "<SECRET_KEY>"
  }
}
```

- Leave out the keys to use the default AWS chain (environment, profile, instance or pod role).
- `s3_path` starts with `/`.
- Policy: `s3:ListBucket`, `s3:GetBucketLocation` on the bucket; `s3:GetObject`, `s3:PutObject`,
  `s3:DeleteObject` on `bucket/*`. Docs: [Parquet IAM](https://olake.io/docs/writers/parquet/permission).

## MinIO

Same as S3 plus `"s3_endpoint": "http://<MINIO_HOST>:9000"` and the MinIO keys. Region can be any value
(`us-east-1`). The bucket must exist.

## GCS

S3 interoperability: create HMAC keys for a service account
([HMAC keys](https://cloud.google.com/storage/docs/authentication/hmackeys)), then

```json
{
  "type": "PARQUET",
  "writer": {
    "s3_bucket": "<GCS_BUCKET>",
    "s3_region": "<BUCKET_LOCATION>",
    "s3_path": "/olake",
    "s3_endpoint": "https://storage.googleapis.com",
    "s3_access_key": "<HMAC_ACCESS_ID>",
    "s3_secret_key": "<HMAC_SECRET>"
  }
}
```

The service account needs `roles/storage.objectAdmin` on the bucket.

## Azure Blob / ADLS Gen2

```json
{
  "type": "PARQUET",
  "writer": {
    "storage_type": "Azure",
    "azure_auth_type": "shared-key",
    "azure_storage_account_name": "<ACCOUNT>",
    "azure_storage_account_key": "<ACCOUNT_KEY>",
    "azure_container_name": "<CONTAINER>",
    "azure_path": "/olake"
  }
}
```

| `azure_auth_type` | Fields |
| --- | --- |
| `shared-key` | `azure_storage_account_name`, `azure_storage_account_key` |
| `sas-token` | `azure_storage_account_name`, `azure_sas_token` (needs create, write, list, delete) |
| `connection-string` | `azure_connection_string` |
| `managed-or-workload-identity` | `azure_storage_account_name`; optional `azure_client_id` for a user-assigned identity. The identity needs **Storage Blob Data Contributor**. |

Azurite (local emulator): `"azure_endpoint": "http://<HOST>:10000/<ACCOUNT>"`.
