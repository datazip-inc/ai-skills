# Snowflake Horizon catalog

`"catalog_type": "horizon"`. OLake sends it as `rest` and asks for vended credentials
(`rest_access_delegation: vended-credentials`), so no storage keys go in `destination.json`.

```json
{
  "type": "ICEBERG",
  "writer": {
    "catalog_type": "horizon",
    "rest_catalog_url": "<HORIZON_ICEBERG_REST_URL>",
    "iceberg_s3_path": "<CATALOG_OR_DATABASE_NAME>",
    "rest_auth_type": "Programmatic Access Token (PAT)",
    "credential": "<CREDENTIAL>",
    "scope": "<SCOPE>",
    "aws_region": "<REGION>"
  }
}
```

- `scope` is required for Horizon.
- Auth types: `Programmatic Access Token (PAT)` and `Key-Pair Authentication` use `credential`
  (Key-Pair also `oauth2_uri`); `External OAuth` uses `token`.
- Field list for this catalog: [../config.md](../config.md). Get the URL, scope and role setup from the
  Snowflake account admin.
