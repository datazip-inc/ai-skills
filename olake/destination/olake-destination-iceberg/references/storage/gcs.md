# Google Cloud Storage

Two supported paths at this version:

| Catalog | `iceberg_s3_path` | Credentials |
| --- | --- | --- |
| `biglake` | `gs://<bucket>` | `gcp_service_account_json` in `destination.json` ([../catalogs/biglake.md](../catalogs/biglake.md)) |
| `hive` (Dataproc Metastore) | `gs://<bucket>/<path>` | Application Default Credentials in the container |

Hive on GCS: mount a service-account key and point ADC at it:

```bash
docker run --rm -v "<CONFIG_DIR>:/mnt/config" -v "<KEY_FILE>:/mnt/gcp/key.json:ro" \
  -e GOOGLE_APPLICATION_CREDENTIALS=/mnt/gcp/key.json \
  olakego/source-<source>:<tag> sync ...
```

On GKE or a GCE VM, Workload Identity or the VM service account works without a key.
The service account needs `roles/storage.objectAdmin` on the bucket. Leave all S3 fields out.
Docs: [Iceberg on Google Cloud](https://olake.io/docs/writers/iceberg/gcp).
