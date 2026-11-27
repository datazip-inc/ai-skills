---
name: olake-troubleshoot
description: "Find why an OLake run failed: get the log, name the failing stage, match the log against every skill's error table with one script, apply the fix. Use on any OLake error, failed check, discover or sync, a stuck job, or a log the user pastes."
metadata:
  parent: olake-protocol
  status: experimental
---

# Troubleshoot an OLake run

Every OLake skill has a Common errors table. `scripts/triage_logs.py` reads all of them and prints
only the rows that match the log, so the whole log never has to be read into the conversation.

## When to use

- A `check`, `discover` or `sync` fails, a job in the UI fails, or the user pastes an error.
- A sync runs but the data is wrong: missing rows, duplicates, a single `data` column.
- Not covered: setting up a source or destination for the first time → the driver or destination skill.

## Inputs to collect

| Input | Example | Where it comes from |
| --- | --- | --- |
| Run mode | CLI, docker compose, Helm | User |
| Failing step | `check --destination` | User, or the `run_sync.sh` summary |
| Log | `<CONFIG_DIR>/sync.log` | [references/collect-logs.md](references/collect-logs.md) |

## Prerequisites

- [ ] The log is saved to a file, or can be piped. Ask the user to remove passwords before pasting.

## Steps

1. Get the log for the failing step: [references/collect-logs.md](references/collect-logs.md).
   `olake-protocol/scripts/run_sync.sh` already saves one log per stage and runs step 2 on failure.
2. Match it:
   ```bash
   python3 scripts/triage_logs.py <log file>          # or: <command> 2>&1 | python3 scripts/triage_logs.py -
   ```
   Each match prints the skill, the error row (cause and fix) and the log line that matched.
3. One match: apply its fix, then rerun only the failed stage (`run_sync.sh --stages <stage>`).
   Several: fix the earliest stage first (table below).
4. No match: the script prints the last error lines. Name the stage from the table, load that
   skill and search its `references/` for the key words of the error line.
5. After the fix works, tell the user which row fixed it. If no row matched, suggest adding one
   to that skill's Common errors table.

| Stage | Log sign | Skill to load |
| --- | --- | --- |
| Deploy | UI not reachable, worker or Temporal not running | `olake-deploy-docker-compose`, `olake-deploy-helm` |
| Check source | `connectionStatus` `FAILED` in `check-source.log` | the driver skill |
| Check destination | `FAILED` in `check-destination.log`; catalog or storage errors | the destination skill |
| Discover | no streams, missing tables | the driver skill, `olake-protocol` |
| Backfill | errors after the backfill or chunk lines | `olake-driver-abstract`, the driver skill |
| CDC | replication slot, binlog, oplog, LSN or offset errors | the driver skill |
| Writer | Java, gRPC, Iceberg or Parquet errors | `olake-destination-abstract`, the destination skill |

## Verify

- The failed stage passes on rerun, and `run_sync.sh` ends with `ok   sync`.
- For data problems: the destination count matches the source (`olake-protocol` Verify).

## Common errors

| Error | Cause | Fix |
| --- | --- | --- |
| `No known error matched` from the script | The error is not in any table yet | Step 4. |
| `Cannot connect to the Docker daemon` | Docker is not running | Start Docker, rerun. |
| `pull access denied` or `manifest unknown` | Wrong image name or tag | Use `olakego/source-<source>:<tag>` with a released tag. |

## Next

- Rerun from where it stopped: `olake-protocol` (step 7, `--state`).
- Logs per run mode: [references/collect-logs.md](references/collect-logs.md).

## Rules

- Never read a whole log into the conversation. Use the script, or `grep` and `tail` for one stage.
- Logs and configs can hold passwords: never print them; ask the user to redact pasted logs.
- A fix that drops a replication slot, clears state or clears the destination needs the user's
  confirmation first.
