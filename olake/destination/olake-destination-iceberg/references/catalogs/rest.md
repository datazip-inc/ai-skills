# REST catalog

`"catalog_type": "rest"`. Generated field list: [../config.md](../config.md). Vendor REST catalogs
(Polaris, Lakekeeper, Nessie, Unity, S3 Tables, BigLake, Horizon) have their own `catalog_type` and set
some fields for you.

| Field | Needed | Notes |
| --- | --- | --- |
| `rest_catalog_url` | yes | Base URL; OLake calls `<url>/v1/...`. Check it: `curl <url>/v1/config`. |
| `iceberg_s3_path` | yes | Warehouse location, `s3://<bucket>/<path>`. |
| `aws_region` | yes | Any region string for MinIO (`us-east-1`). |
| `catalog_name` | no | Lowercase letters and `_`. Default `olake_iceberg`. |
| `token` | no | Bearer token for the catalog. |
| `rest_auth_type`, `oauth2_uri`, `credential`, `scope` | no | OAuth2 client credentials: `credential` is `<client_id>:<client_secret>`. |
| `rest_signing_v_4`, `rest_signing_name`, `rest_signing_region` | no | AWS SigV4 signed catalogs. |
| `no_identifier_fields` | no | `true` for catalogs that reject identifier fields. |

Local POC catalog: [../../assets/rest-minio/docker-compose.yml](../../assets/rest-minio/docker-compose.yml)
runs `tabulario/iceberg-rest` with a SQLite catalog in the `catalog-data` volume, on MinIO bucket
`warehouse`. Tables survive `docker compose restart` and `down`; `down -v` deletes them.

Check the catalog by hand (read-only):

```bash
curl -s <url>/v1/namespaces
curl -s <url>/v1/namespaces/<namespace>/tables
```

Add `-H "Authorization: Bearer <TOKEN>"` when the catalog needs a token.
