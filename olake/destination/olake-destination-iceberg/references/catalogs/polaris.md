# Apache Polaris (and Snowflake Open Catalog)

`"catalog_type": "polaris"`: OLake sends it as `rest`.
Docs: [REST → Polaris](https://olake.io/docs/writers/iceberg/catalog/rest?rest-catalog=polaris),
[Polaris IAM setup](https://olake.io/docs/writers/iceberg/polaris-iam-setup).

```json
{
  "type": "ICEBERG",
  "writer": {
    "catalog_type": "polaris",
    "rest_catalog_url": "http://<POLARIS_HOST>:8181/api/catalog",
    "iceberg_s3_path": "<POLARIS_CATALOG_NAME>",
    "rest_auth_type": "OAuth2",
    "oauth2_uri": "http://<POLARIS_HOST>:8181/api/catalog/v1/oauth/tokens",
    "credential": "<CLIENT_ID>:<CLIENT_SECRET>",
    "scope": "PRINCIPAL_ROLE:ALL",
    "aws_region": "<REGION>"
  }
}
```

- `iceberg_s3_path` is the Polaris **catalog name**. The catalog's storage config (S3 role ARN, or
  MinIO endpoint) lives in Polaris.
- The principal needs a principal role bound to a catalog role with `CATALOG_MANAGE_CONTENT` (or
  `TABLE_WRITE_DATA` plus namespace and table create).
- Polaris vends S3 credentials; storage keys in `destination.json` are only needed when it does not.

## Local Polaris on MinIO

Tested with `apache/polaris:1.9.0` on the POC network. Polaris cannot vend credentials for MinIO, so
the catalog sets `stsUnavailable` and `destination.json` carries the MinIO keys.

1. Start Polaris with bootstrap credentials and MinIO keys in its environment:
   `POLARIS_BOOTSTRAP_CREDENTIALS=POLARIS,<CLIENT_ID>,<CLIENT_SECRET>`,
   `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`.
2. Get a token: `POST /api/catalog/v1/oauth/tokens` with `grant_type=client_credentials`,
   `client_id`, `client_secret`, `scope=PRINCIPAL_ROLE:ALL`.
3. Create the catalog (`POST /api/management/v1/catalogs`):
   ```json
   {"catalog": {"name": "olake", "type": "INTERNAL",
     "properties": {"default-base-location": "s3://warehouse/polaris"},
     "storageConfigInfo": {"storageType": "S3", "allowedLocations": ["s3://warehouse/polaris"],
       "endpoint": "http://minio:9000", "endpointInternal": "http://minio:9000",
       "pathStyleAccess": true, "stsUnavailable": true}}}
   ```
4. Grant `CATALOG_MANAGE_CONTENT` to the catalog role `catalog_admin`
   (`PUT .../catalogs/olake/catalog-roles/catalog_admin/grants`), and give that role to the principal
   role `service_admin` (`PUT .../principal-roles/service_admin/catalog-roles/olake`).
5. In `destination.json` add `"s3_endpoint": "http://minio:9000"`, `"s3_path_style": true`,
   `"s3_use_ssl": false` and the MinIO keys to the example above.
