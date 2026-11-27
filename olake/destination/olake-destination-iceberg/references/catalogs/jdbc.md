# JDBC catalog

`"catalog_type": "jdbc"`. Metadata in a relational database (Postgres, MySQL), data in S3 or MinIO.
Docs: [JDBC catalog](https://olake.io/docs/writers/iceberg/catalog/jdbc).

```json
{
  "type": "ICEBERG",
  "writer": {
    "catalog_type": "jdbc",
    "catalog_name": "olake_iceberg",
    "jdbc_url": "jdbc:postgresql://<DB_HOST>:5432/iceberg",
    "jdbc_username": "<JDBC_USER>",
    "jdbc_password": "<JDBC_PASSWORD>",
    "iceberg_s3_path": "s3://<BUCKET>/<PATH>",
    "aws_region": "us-east-1",
    "aws_access_key": "<ACCESS_KEY>",
    "aws_secret_key": "<SECRET_KEY>",
    "s3_endpoint": "http://<MINIO_HOST>:9000",
    "s3_path_style": true,
    "s3_use_ssl": false
  }
}
```

- The catalog user needs `CREATE TABLE`, `SELECT`, `INSERT`, `UPDATE`, `DELETE` in the catalog
  database: Iceberg creates `iceberg_tables` and `iceberg_namespace_properties` on first use.
- `catalog_name` is a row key in those tables: every engine that reads the tables must use the same
  name. Lowercase letters and `_` only.
- Query engines read the same JDBC database and bucket (Spark: `type=jdbc`, `uri=<jdbc_url>`).

## Errors

| Error | Fix |
| --- | --- |
| `jdbc_url is required when using JDBC catalog` | Set `jdbc_url`. |
| `Connection refused` to the database | Host or port wrong from inside the container. |
| `permission denied for schema public` | Grant `CREATE` on the schema to the catalog user. |
