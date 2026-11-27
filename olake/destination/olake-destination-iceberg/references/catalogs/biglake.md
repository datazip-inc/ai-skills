# Google BigLake metastore

`"catalog_type": "biglake"`. OLake sends it as `rest` and uses Google auth
(`org.apache.iceberg.gcp.auth.GoogleAuthManager`). Data in GCS.

```json
{
  "type": "ICEBERG",
  "writer": {
    "catalog_type": "biglake",
    "rest_catalog_url": "https://biglake.googleapis.com/iceberg/v1/restcatalog",
    "iceberg_s3_path": "gs://<BUCKET>",
    "rest_auth_type": "GCP",
    "gcp_service_account_json": "<SERVICE_ACCOUNT_JSON>",
    "gcp_project_id": "<PROJECT_ID>"
  }
}
```

- `gcp_service_account_json` is the key file content, inline. Never print it; ask the user to paste it
  into the file.
- `gcp_project_id`: needed for multi-bucket catalogs (billing and routing header).
- The service account needs BigLake editor on the catalog and `roles/storage.objectAdmin` on the bucket.
- Query: BigQuery (BigLake Iceberg tables) or Spark with the same catalog.
