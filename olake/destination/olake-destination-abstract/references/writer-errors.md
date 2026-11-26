# Writer errors

Source: [`destination/`](https://github.com/datazip-inc/olake-go/tree/master/destination). Read the
first `error` line in `olake.log`; for Iceberg the cause is the Java exception name in it.

| Seen in the log | Class | Check |
| --- | --- | --- |
| `UnknownHostException`, `ConnectException`, `NoRouteToHostException`, `grpc.Unavailable` | Network | Catalog or storage host from inside the container. Not `localhost`; use `host.docker.internal` or the host IP. |
| `SocketTimeoutException`, `ConnectTimeoutException`, `grpc.DeadlineExceeded` | Timeout | Endpoint reachable? Firewall, VPC, security group. |
| `SSLHandshakeException`, `CertificateException` | TLS | `s3_use_ssl` matches the endpoint; trusted certificate. |
| `NotAuthorizedException`, `LoginException`, `TokenResponseException` | Auth | Catalog token or credentials. |
| `AccessDeniedException`, `ForbiddenException`, S3 `AccessDenied` | Permission | Keys or role can list, read and write the bucket path and create catalog namespaces and tables. |
| `NoSuchTableException`, `NoSuchNamespaceException`, `NoSuchBucket` | Not found | Bucket, warehouse or namespace exists; `iceberg_s3_path` is right. |
| `CommitFailedException`, `ConcurrentModificationException`, `LockException` | Conflict | Another job writes the same table. Run one job per table; rerun with `--state`. |
| `CommitStateUnknownException` | Catalog | The commit may or may not have landed. Check the table, then rerun with `--state`. |
| `ValidationException` | Schema | Records do not fit the table: incompatible type change. See [columns.md](columns.md#schema-changes). |
| `OutOfMemoryError` | Resources | Give the container more memory, or lower `--destination-buffer-size`. |
| `failed to start iceberg java writer` | Writer start | The Java writer did not start: memory, or port `50051` already in use. |
| `no matches found for partition regex` | Config | [partitioning.md](partitioning.md). |

After the fix, rerun with the same files and `--state`: committed data is not written twice.
