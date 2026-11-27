---
name: olake-driver-s3
description: "Read files from Amazon S3 or MinIO into OLake: source.json, bucket and path_prefix layout, CSV, JSON, Parquet and XML, IAM permissions, incremental by file modification time. Use when the source is files in S3 or S3-compatible storage."
metadata:
  parent: olake-driver-abstract
  status: experimental
---

# S3 source

Image: `olakego/source-s3:<tag>`. Sync modes: `full_refresh`, `incremental` (new or changed files,
by last modified time). The run (`check`, `discover`, `sync`) is in `olake-protocol`.

## When to use

- The source is files in an S3 bucket or MinIO.
- `check` fails on the bucket.

## Inputs to collect

Ask only for what is missing. Never echo a password or key back.

| Input | Example | Where it comes from |
| --- | --- | --- |
| `bucket_name`, `region` | `my-bucket`, `us-east-1` | User |
| `path_prefix` | `exports/` | User. Each first-level folder under it becomes one stream. |
| `file_format`, `compression` | `csv`, `none` | User. `csv`, `json`, `parquet` or `xml`; `none`, `gzip` or `zip`. |
| `access_key_id`, `secret_access_key` | `<ACCESS_KEY>`, `<SECRET_KEY>` | User. Leave out to use the instance role. |
| `endpoint` | `http://minio:9000` | MinIO or other S3-compatible storage only. |

## Prerequisites

- [ ] The keys or role allow `s3:ListBucket` on the bucket and `s3:GetObject` on the prefix.
- [ ] Files are laid out as `<path_prefix>/<stream>/<files>`: one folder per stream, one format per
      source.

## Steps

1. Write `source.json` in the config folder (example below). Every field:
   [references/config.md](references/config.md).
2. `check` the source, then `discover` (`olake-protocol` steps 2 to 4).
3. In `selected_streams.json`, set the sync mode per stream.
4. Sync, then rerun with `--state` (`olake-protocol` steps 6 and 7).

```json
{
  "bucket_name": "<BUCKET_NAME>",
  "region": "us-east-1",
  "path_prefix": "<PATH_PREFIX>",
  "access_key_id": "<ACCESS_KEY>",
  "secret_access_key": "<SECRET_KEY>",
  "file_format": "csv",
  "compression": "none",
  "csv": { "has_header": true, "delimiter": "," },
  "max_threads": 3
}
```

JSON files: `"file_format": "json"` and `"json": { "line_delimited": true }` for JSONL. Each record gets
`_last_modified_time` from its file.

## Verify

- `check` prints `"status":"SUCCEEDED"`.
- Row count on the destination equals the number of records in the stream's files.
- Incremental: add a file to the stream folder, rerun with `--state`, and find only its rows added.

## Common errors

| Error | Cause | Fix |
| --- | --- | --- |
| `failed to access bucket <bucket>` | Bucket name, endpoint or keys wrong | MinIO: set `endpoint`; AWS: check the region and `s3:ListBucket`. |
| `access_key_id and secret_access_key must be provided together or both omitted` | One key missing | Set both, or neither for an IAM role. |
| `no files found for stream: <stream>` | Files not under `<path_prefix>/<stream>/`, or `file_pattern` too narrow | Fix the layout or the pattern. |
| `failed to convert '<value>' to <type>` | CSV value does not match the inferred type | Clean the file, or keep the column as string. |

## Next

- The run, reruns and state: `olake-protocol`.
- Sync modes in general: `olake-driver-abstract`.
- Destination setup: `olake-destination-abstract`, then the destination skill.

## Rules

- Use `<SECRET_KEY>` placeholders; never print secrets.
