---
name: olake-driver-oracle
description: "Connect Oracle Database to OLake: source.json with service name or SID, read grants, full_refresh and incremental (no CDC). Use when the source is Oracle, or on ORA- errors."
metadata:
  parent: olake-driver-abstract
  status: experimental
---

# Oracle source

Image: `olakego/source-oracle:<tag>`. Sync modes: `full_refresh`, `incremental`. No CDC: deletes are
not captured. The run (`check`, `discover`, `sync`) is in `olake-protocol`.

## When to use

- The source is Oracle: self-hosted, Docker, RDS, OCI.
- `check` fails on an Oracle host.

## Inputs to collect

Ask only for what is missing. Never echo a password or key back.

| Input | Example | Where it comes from |
| --- | --- | --- |
| `host`, `port` | `ora.internal`, `1521` | User. From a container, `localhost` is the container: use `host.docker.internal` or the Docker network service name. |
| `connection_type` | `service_name` or `sid` | User or DBA |
| `service_name` or `sid` | `ORCLPDB1` | User or DBA. A pluggable database is reached by service name. |
| `username`, `password` | `OLAKE_USER`, `<PASSWORD>` | User or DBA |

## Prerequisites

- [ ] `GRANT CREATE SESSION TO <user>;` and `SELECT` on every table to sync (or
      `GRANT SELECT ANY TABLE TO <user>;`).
- [ ] The listener accepts connections from where OLake runs (firewall, security group).

## Steps

1. Write `source.json` in the config folder (example below). Every field:
   [references/config.md](references/config.md).
2. `check` the source, then `discover` (`olake-protocol` steps 2 to 4).
3. In `selected_streams.json`, set the sync mode per stream (`incremental` also needs `cursor_field`, a column that only grows).
4. Sync, then rerun with `--state` (`olake-protocol` steps 6 and 7).

```json
{
  "host": "<HOST>",
  "port": 1521,
  "connection_type": "service_name",
  "service_name": "<SERVICE_NAME>",
  "username": "<USERNAME>",
  "password": "<PASSWORD>",
  "max_threads": 3
}
```

Oracle stores unquoted user names in uppercase. Write `username` in uppercase (`OLAKE`, not `olake`):
a lowercase name fails `check` with `ORA-01017: invalid credential or not authorized; logon denied`,
even when `sqlplus` accepts it.

## Verify

- `check` prints `"status":"SUCCEEDED"`.
- Row count on the destination equals `SELECT COUNT(*) FROM <owner>.<table>` on the source.

## Common errors

| Error | Cause | Fix |
| --- | --- | --- |
| `ORA-01017: invalid credential or not authorized; logon denied` | Username not uppercase | Write `username` in uppercase, even if `sqlplus` accepts it lowercase. |
| `ORA-12514` / `ORA-12505` | Wrong service name or SID | Use the service the listener registers (`lsnrctl status`). |
| `discover` finds no streams | No `SELECT` on the owner's tables | Grant `SELECT`, or `SELECT ANY TABLE`. |

## Next

- The run, reruns and state: `olake-protocol`.
- Sync modes in general: `olake-driver-abstract`.
- Destination setup: `olake-destination-abstract`, then the destination skill.
- Source column types and what they become: [references/type-mapping.md](references/type-mapping.md).

## Rules

- Use `<PASSWORD>` placeholders; never print secrets.
