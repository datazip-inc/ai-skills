# OLake agent skills

This repo holds agent skills for [OLake](https://olake.io): replicate databases, Kafka and S3 to Apache
Iceberg or Parquet, then verify and troubleshoot the run.

## For any OLake task

1. Read [`olake/olake-protocol/SKILL.md`](olake/olake-protocol/SKILL.md) first. It routes to the right
   source, destination and deploy skill and runs every step with `olake/olake-protocol/scripts/run_sync.sh`.
2. On an error, a failed run or a pasted log, use
   [`olake/olake-troubleshoot/SKILL.md`](olake/olake-troubleshoot/SKILL.md).
3. Open a skill's `references/` file only when a step points to it. Run its `scripts/` instead of reading
   whole logs.

## Rules

- Write secrets as placeholders (`<PASSWORD>`, `<SECRET_KEY>`). Never print them back.
- Confirm with the user before anything that deletes data: `clear`, `docker compose down -v`, dropping a
  slot or a table.
- Skills are checked against the OLake release in [`OLAKE_VERSION`](OLAKE_VERSION).

## Working on the skills

Layout, checks and the contribution flow are in [`README.md`](README.md#contributing).
