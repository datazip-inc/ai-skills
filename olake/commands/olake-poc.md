---
description: Set up an OLake POC end to end, from a source to Iceberg or Parquet, and verify the data
argument-hint: "[source] to [destination], e.g. postgres to iceberg"
---

Run an OLake POC for: $ARGUMENTS

1. Load the `olake-protocol` skill and follow it. Ask only for the inputs that are still missing
   (source, destination, run mode); with no destination given, offer the local Iceberg stack from
   `olake-destination-iceberg`.
2. Load only the driver and destination skills for this combination.
3. Run every stage with `olake-protocol/scripts/run_sync.sh` and report its summary, not the logs.
4. Finish with the Verify section of `olake-protocol`: row counts on the source and the destination.
