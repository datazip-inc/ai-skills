# How OLake fits together

- **OLake Go drivers**: one Docker image per source, `olakego/source-<source>`. Each image has the
  commands `spec`, `check`, `discover`, `sync` and `clear-destination`, and writes to every destination.
- **Destinations**: Apache Iceberg (through a bundled Java writer, using a catalog such as REST, Glue,
  Hive or JDBC, on S3, MinIO, GCS or Azure) and Parquet (local, S3, GCS or Azure).
- **OLake UI**: web app plus API. A worker (Temporal) runs the driver images for each check,
  discover and sync, on Docker (compose) or Kubernetes (helm).
- **OLake Fusion**: optional compaction and maintenance for the Iceberg tables OLake writes.

```text
OLake UI ── runs jobs via ──▶ worker ── launches ──▶ olakego/source-<source> ──▶ Iceberg / Parquet
CLI user ────────────────────── docker run ───────▶ olakego/source-<source> ──▶ Iceberg / Parquet
```

Reading order for a run: source (`check`) → destination (`check`) → `discover` → choose streams →
`sync` → rerun with state.

Deep dive: https://olake.io/blog/olake-architecture-deep-dive
