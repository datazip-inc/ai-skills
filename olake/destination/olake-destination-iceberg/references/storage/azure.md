# Azure ADLS Gen2

At this version OLake writes to ADLS Gen2 through a REST catalog that vends credentials, such as
Lakekeeper. Docs: [Iceberg on Azure](https://olake.io/docs/writers/iceberg/azure).

1. Storage account with **Hierarchical namespace** on, and a container (`warehouse-dev`).
2. An Entra app registration (client id, tenant id, client secret) with **Storage Blob Data Owner** and
   **Storage Blob Delegator** on the storage account.
3. In Lakekeeper, a warehouse with storage type Azure, client credentials, the account name and the
   container as filesystem.
4. `destination.json`:

```json
{
  "type": "ICEBERG",
  "writer": {
    "catalog_type": "lakekeeper",
    "rest_catalog_url": "http://<LAKEKEEPER_HOST>:8181/catalog",
    "iceberg_s3_path": "<WAREHOUSE_NAME>",
    "rest_auth_type": "None",
    "s3_endpoint": "https://<STORAGE_ACCOUNT>.dfs.core.windows.net",
    "aws_region": "<REGION>"
  }
}
```

No storage keys in `destination.json`: Lakekeeper hands out short-lived SAS tokens. The Azure secret
lives only in Lakekeeper.
