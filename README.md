# ai-skills

Agent skills for [OLake](https://github.com/datazip-inc/olake), written in the open
[`SKILL.md`](https://agentskills.io) format used by Claude Code, Cursor, Codex, Cortex Code and others.

The skills cover two uses:

- **Run OLake end to end**: deploy, connect a source, configure a destination, sync, verify and
  troubleshoot, guided by your agent.
- **Develop OLake features**: plan and deliver a change across `olake`, `olake-ui`, `olake-helm` and
  `olake-docs`, and keep the skills in step with each release.

## Install

Claude Code:

```text
/plugin marketplace add datazip-inc/ai-skills
/plugin install olake@olake-ai-skills
```

Any agent that supports the skills CLI:

```bash
npx skills add datazip-inc/ai-skills
```

Then ask your agent, for example: "Set up OLake to replicate my Postgres to Iceberg with a REST catalog
on MinIO".

## Skill map

The `olake/` folder mirrors the [olake repo](https://github.com/datazip-inc/olake) layout.

| Folder | Skill | What it does |
| --- | --- | --- |
| `olake/olake-protocol/` | `olake-protocol` | Base skill: spec, check, discover, sync, clear and verify for any source and destination |
| `olake/drivers/olake-driver-abstract/` | `olake-driver-abstract` | Shared source behaviour: sync modes, backfill, CDC, incremental, prerequisites |
| `olake/drivers/olake-driver-postgres/` | `olake-driver-postgres` | Postgres source |
| `olake/destination/olake-destination-abstract/` | `olake-destination-abstract` | Shared writer behaviour: normalization, partitioning, writer errors |
| `olake/destination/olake-destination-iceberg/` | `olake-destination-iceberg` | Iceberg destination: catalogs, storage, deletes |
| `olake/deploy/olake-deploy-docker-compose/` | `olake-deploy-docker-compose` | Run OLake locally with docker compose |
| `olake/olake-troubleshoot/` | `olake-troubleshoot` | Logs, stage triage, error to fix |

`olake/features/` holds cross-cutting feature skills, and `olake/experimental/` holds skills for features
that are on `staging` and not yet released.

## Contributing

1. Copy `template/SKILL.md.tmpl` to `olake/<group>/<skill-name>/SKILL.md`. The folder name must match
   `name` in the frontmatter.
2. Add the skill path to `olake/.claude-plugin/plugin.json`.
3. Run the checks:

   ```bash
   pip install -r tools/requirements.txt
   python tools/validate.py
   python tools/check_links.py
   ```
