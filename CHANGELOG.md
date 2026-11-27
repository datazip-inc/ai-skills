# Changelog

All notable changes to the OLake agent skills. Versions match `version` in
`olake/.claude-plugin/plugin.json`.

## Unreleased (0.1.0)

### Added

- `olake-protocol`: entry skill for spec, check, discover, sync, clear and verify, with
  `scripts/run_sync.sh`.
- `olake-troubleshoot`: stage triage and `scripts/triage_logs.py`, which matches a log against every
  skill's Common errors table.
- `olake-driver-abstract` and `olake-driver-postgres`.
- `olake-destination-abstract` and `olake-destination-iceberg`, with a local REST catalog + MinIO stack.
- `/olake-poc` and `/olake-debug` commands.
- A `UserPromptSubmit` hook that points the agent to `olake-protocol` on OLake prompts.
- `AGENTS.md` and `CLAUDE.md`, so a cloned repo works with no install.
- Apache-2.0 licence.
- `tools/validate.py`, `tools/check_links.py` and `tools/measure_tokens.py`.
- `tools/gen_matrix.py`: writes `compatibility-matrix.md` from the driver, destination and deploy
  skills in the tree; `--ref <branch>` previews another branch.
- `OLAKE_VERSION` moved to `olake/OLAKE_VERSION` so it ships with the plugin. `run_sync.sh` reads its
  default image tag from it, and `validate.py` checks that olake links use that tag.
