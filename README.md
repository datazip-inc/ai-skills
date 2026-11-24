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
/plugin install olake-go@olake-ai-skills            # run OLake
/plugin install olake-ui@olake-ai-skills           # run and use the OLake UI
/plugin install olake-helm@olake-ai-skills         # run OLake on Kubernetes
/plugin install olake-dev@olake-ai-skills          # test OLake code changes across repos (developers)
```

Any agent that supports the skills CLI:

```bash
npx skills add datazip-inc/ai-skills
```

Then ask your agent, for example: "Set up OLake to replicate my Postgres to Iceberg with a REST catalog
on MinIO".

## Skill map

Each product plugin is a top-level folder that mirrors one OLake repo.
Developer tooling, which is not a product, lives under `root/`.

| Plugin | For | Contents |
| --- | --- | --- |
| `olake-go/` | Users | Run OLake: drivers, destinations, deploy, troubleshoot. Mirrors the [olake repo](https://github.com/datazip-inc/olake) layout |
| `root/olake-dev/` | Developers | `olake-e2e-test`: build olake, olake-ui and olake-helm from chosen branches, deploy them together and test a change end to end |
| `olake-ui/` | Users and developers | `olake-ui-deploy`: run the OLake UI stack with docker compose (install, settings, upgrade, tear down). `olake-ui-manage`: create sources, destinations and jobs, sync and read run logs, in the UI or through the API. Planned: GitOps |
| `olake-helm/` | Users and developers | `olake-helm-deploy`: run OLake on Kubernetes with the Helm chart (install, values for storage, encryption, access, external databases, registry and job placement, upgrade, uninstall). Planned: how the worker runs task pods (`olake-worker`) |

`olake-dev` has optional settings for the local paths of the three code repos. They are only needed to test local, unpushed changes; pushed branches are fetched automatically.

Skills in `olake-go/`:

| Folder | Skill | What it does |
| --- | --- | --- |
| `olake-go/olake-protocol/` | `olake-protocol` | Base skill: spec, check, discover, sync, clear and verify for any source and destination |
| `olake-go/drivers/olake-driver-abstract/` | `olake-driver-abstract` | Shared source behaviour: sync modes, backfill, CDC, incremental, prerequisites |
| `olake-go/drivers/olake-driver-postgres/` | `olake-driver-postgres` | Postgres source |
| `olake-go/destination/olake-destination-abstract/` | `olake-destination-abstract` | Shared writer behaviour: normalization, partitioning, writer errors |
| `olake-go/destination/olake-destination-iceberg/` | `olake-destination-iceberg` | Iceberg destination: catalogs, storage, deletes |
| `olake-go/deploy/olake-deploy-docker-compose/` | `olake-deploy-docker-compose` | Run OLake locally with docker compose |
| `olake-go/olake-troubleshoot/` | `olake-troubleshoot` | Logs, stage triage, error to fix |

`olake-go/features/` holds cross-cutting feature skills, and `olake-go/experimental/` holds skills for features
that are on `staging` and not yet released.

## Contributing

1. Copy `template/SKILL.md.tmpl` to `<plugin>/<group>/<skill-name>/SKILL.md`. The folder name must match
   `name` in the frontmatter.
2. Add the skill path to `<plugin>/.claude-plugin/plugin.json`. A new plugin also needs an entry in
   `.claude-plugin/marketplace.json`: the checks only see plugins listed there.
3. Run the checks:

   ```bash
   pip install -r tools/requirements.txt
   python tools/validate.py
   python tools/check_links.py
   ```
