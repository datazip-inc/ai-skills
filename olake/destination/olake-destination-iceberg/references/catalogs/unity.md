# Databricks Unity Catalog

`"catalog_type": "unity"`. OLake sends it as `rest` and sets `no_identifier_fields: true` (Unity rejects
identifier fields). Docs: [REST → Unity](https://olake.io/docs/writers/iceberg/catalog/rest?rest-catalog=unity).

```json
{
  "type": "ICEBERG",
  "writer": {
    "catalog_type": "unity",
    "rest_catalog_url": "https://<WORKSPACE_URL>/api/2.1/unity-catalog/iceberg-rest",
    "iceberg_s3_path": "<UNITY_CATALOG_NAME>",
    "rest_auth_type": "Personal Access Token (PAT)",
    "token": "<DATABRICKS_TOKEN>"
  }
}
```

- `iceberg_s3_path` is the Unity **catalog name**. Unity vends storage credentials: no S3 fields.
- Auth: `Personal Access Token (PAT)` or `OAuth2 U2M` / `Token Federation` (`token`); `OAuth2 M2M`
  (service principal: `oauth2_uri` `https://<WORKSPACE_URL>/oidc/v1/token`, `credential`
  `<client_id>:<client_secret>`, `scope` `all-apis`).
- The principal needs `USE CATALOG`, `USE SCHEMA`, `CREATE SCHEMA`, `CREATE TABLE`, `EXTERNAL USE SCHEMA`
  on the catalog, and the metastore must allow external data access.
