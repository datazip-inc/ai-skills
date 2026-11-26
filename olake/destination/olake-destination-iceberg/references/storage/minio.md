# MinIO and S3 storage

| Field | MinIO | AWS S3 |
| --- | --- | --- |
| `s3_endpoint` | `http://minio:9000` (address reachable from the OLake container) | leave out |
| `s3_path_style` | `true` (OLake sets it whenever `s3_endpoint` is set) | leave out |
| `s3_use_ssl` | `false` for `http://`, `true` for `https://` | leave out |
| `aws_region` | `us-east-1` (any value) | the bucket's region |
| `aws_access_key`, `aws_secret_key` | MinIO user's keys | keys, or leave out for the instance role / default chain |
| `aws_session_token` | — | temporary credentials only |

- The bucket in `iceberg_s3_path` must exist before `check`.
- The keys need list, get, put and delete on `<bucket>/<path>/*`.
- The catalog reads the same files: its own storage settings must point at the same bucket. In the
  local stack both use `minio:9000` and keys `admin` / `password`.
- Browse files: MinIO console at `http://localhost:9001` (or `MINIO_CONSOLE_PORT`).
