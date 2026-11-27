# ai-skills

Agent skills for [OLake](https://github.com/datazip-inc/olake-go), written in the open
[`SKILL.md`](https://agentskills.io) format used by Claude Code, Cursor, Codex, Cortex Code and others.

With these skills your agent runs OLake end to end: deploy, connect a source, configure a destination,
sync, verify and troubleshoot. It writes the configs, runs the OLake Docker images, and reads short
summaries of the logs instead of the whole output.

## Install

Pick one. Each needs only `docker`, `bash` and `python3` on the machine.

| Agent | Install |
| --- | --- |
| Claude Code | `/plugin marketplace add datazip-inc/ai-skills`, then `/plugin install olake@olake-ai-skills` |
| Cursor, Codex, Copilot, Cortex Code and other `SKILL.md` agents | `npx skills add datazip-inc/ai-skills` |
| Any agent, no install | `git clone https://github.com/datazip-inc/ai-skills && cd ai-skills`, then start the agent there. `AGENTS.md` (and `CLAUDE.md`) point it to the skills. |
| Any agent that can fetch URLs | Ask it: "Install the OLake skills from https://github.com/datazip-inc/ai-skills" |

The Claude Code plugin also adds `/olake-poc` and `/olake-debug`, and a prompt hook that points the agent
to `olake-protocol` the first time a prompt mentions OLake, or Iceberg or Parquet with a source or a sync.

## Use

Ask your agent, for example:

- "Set up OLake to replicate my Postgres to Iceberg with a REST catalog on MinIO."
- "Run a CDC sync from MySQL to Parquet on S3 and check the row counts."
- "My OLake sync failed, here is the log: ..."

In Claude Code, `/olake-poc postgres to iceberg` starts the POC flow, and `/olake-debug <log>` finds why a
run failed.

The skills write secrets as placeholders, never print them, and ask before anything that deletes data.

## Skill map

The `olake/` folder mirrors the [olake-go repo](https://github.com/datazip-inc/olake-go) layout.

| Folder | Skill | What it does |
| --- | --- | --- |
| `olake/olake-protocol/` | `olake-protocol` | Base skill: spec, check, discover, sync, clear and verify for any source and destination |
| `olake/drivers/olake-driver-abstract/` | `olake-driver-abstract` | Shared source behaviour: sync modes, backfill, CDC, incremental, prerequisites |
| `olake/drivers/olake-driver-postgres/` | `olake-driver-postgres` | Postgres source |
| `olake/drivers/olake-driver-mysql/` | `olake-driver-mysql` | MySQL source |
| `olake/drivers/olake-driver-mongodb/` | `olake-driver-mongodb` | MongoDB source |
| `olake/drivers/olake-driver-mssql/` | `olake-driver-mssql` | SQL Server source |
| `olake/drivers/olake-driver-oracle/` | `olake-driver-oracle` | Oracle source |
| `olake/drivers/olake-driver-db2/` | `olake-driver-db2` | DB2 source |
| `olake/drivers/olake-driver-s3/` | `olake-driver-s3` | S3 source |
| `olake/drivers/olake-driver-kafka/` | `olake-driver-kafka` | Kafka source |
| `olake/destination/olake-destination-abstract/` | `olake-destination-abstract` | Shared writer behaviour: normalization, partitioning, writer errors |
| `olake/destination/olake-destination-iceberg/` | `olake-destination-iceberg` | Iceberg destination: catalogs, storage, deletes |
| `olake/deploy/olake-deploy-docker-compose/` | `olake-deploy-docker-compose` | Run OLake locally with docker compose |
| `olake/deploy/olake-deploy-helm/` | `olake-deploy-helm` | Run OLake on Kubernetes with the Helm chart |
| `olake/olake-troubleshoot/` | `olake-troubleshoot` | Logs, stage triage, error to fix |

`olake/features/` holds cross-cutting feature skills, and `olake/experimental/` holds skills for features
that are on `staging` and not yet released.

## Contributing

1. Copy `template/SKILL.md.tmpl` to `olake/<group>/<skill-name>/SKILL.md`. The folder name must match
   `name` in the frontmatter.
2. Add the skill path to `olake/.claude-plugin/plugin.json` once it is written. Drafts (`TODO` in
   `description`) stay out of it, so they do not ship.

`OLAKE_VERSION` at the repo root is the one
[olake-go release](https://github.com/datazip-inc/olake-go/releases) every skill is verified against.
After re-checking the skills against a new release, bump it there; no skill carries its own version.
3. Run the checks:

   ```bash
   pip install -r tools/requirements.txt
   python tools/validate.py
   python tools/check_links.py
   ```
