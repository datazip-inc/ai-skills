# OLake UI flow

Prerequisite: OLake UI is running (`olake-deploy-docker-compose`), by default at `http://localhost:8000`.

1. **Sources → + Create Source.** Pick the connector, keep the OLake version at the latest stable,
   name it and fill in the connection fields (from the driver skill). Save. The UI runs the
   connection check; it must show success.
2. **Destinations → + Create Destination.** Pick Apache Iceberg or Parquet, then the catalog type,
   and fill in the fields (from the destination skill). Save after the check succeeds.
3. **Jobs → + Create Job.** Name it, set the frequency, select the source and destination. Click
   **Next**: both are validated again.
4. **Streams.** Tick the streams to sync. Click a stream name to set its sync mode, normalization,
   partitioning, data filter and destination database. Save.
5. Run the job now from the job's actions, or wait for the schedule.

Verify: the job run shows as succeeded in the job's history, its logs show synced records, and the
destination query from the destination skill returns the expected row count.

The UI runs the same `check`, `discover` and `sync` commands as the CLI, through the worker.
Job settings, schedules and alerts beyond this flow: `olake-ui-jobs` (later phase).
