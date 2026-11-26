# Postgres troubleshooting

Logs: `logs/sync_<timestamp>/olake.log` in the config folder. Find the
first `ERROR` or `FATAL` line and match it below. Sources:
[`errors.go`](https://github.com/datazip-inc/olake/blob/v1.1.2/drivers/postgres/internal/errors.go),
[`cdc.go`](https://github.com/datazip-inc/olake/blob/v1.1.2/drivers/postgres/internal/cdc.go),
[olake.io troubleshooting](https://olake.io/docs/connectors/postgres#troubleshooting).

## Config validation (before connecting)

| Error (verbatim) | Fix |
| --- | --- |
| `empty host name` | Set `host`. |
| `host should not contain http or https` | Use the bare host name: `db.example.com`, not `https://db.example.com`. |
| `invalid port number: must be between 1 and 65535` | Fix `port`. |
| `database name is required` | Set `database`. |
| `schemas[<i>] must not be blank` | Remove empty strings from `schemas`. |
| `failed to validate ssl config` | `verify-ca` / `verify-full` need `server_ca` (inline) or `server_ca_path` (path). |

## Connection

| Error (verbatim) | Cause | Fix |
| --- | --- | --- |
| `failed to ping database: ... connect: connection refused` | Nothing listens at `host:port` from inside the container | From Docker use `host.docker.internal` or the service name; check firewall and security group. |
| `... i/o timeout` / `no such host` | Network or DNS | Check the host name and that OLake's network can reach it. |
| `no pg_hba.conf entry for host ... no encryption (SQLSTATE 28000)` | SSL required, or OLake's IP not allowed | `"ssl": {"mode": "require"}`; else add a `pg_hba.conf` line. |
| `password authentication failed for user "<user>"` (`28P01`) | Wrong credentials | Re-enter user and password. |
| `database "<db>" does not exist` (`3D000`) | Wrong `database` | Fix the name (case-sensitive). |
| `permission denied for table <t>` / `for schema <s>` (`42501`) | Missing `SELECT` or `USAGE` | Grants in [prerequisites.md](prerequisites.md#read-access). |
| `too many connections` / `remaining connection slots are reserved` (`53300`) | Server at `max_connections` | Lower `max_threads`, or free connections. |
| `failed to setup SSH connection` | Tunnel config | Check `ssh_config` host, port, user and key; the bastion must reach the database. |

## CDC

| Error (verbatim) | Cause | Fix |
| --- | --- | --- |
| `required CDC prerequisites not met: wal_level` | `wal_level` is not `logical` | [cloud-variants.md](cloud-variants.md); restart needed. |
| `required CDC prerequisites not met: replication_privilege` | User cannot open replication connections | `ALTER ROLE <user> WITH REPLICATION;` (RDS: `GRANT rds_replication TO <user>;`) |
| `required CDC prerequisites not met: replication_slot` with `slot "<s>" not found` | Slot missing | `SELECT pg_create_logical_replication_slot('<s>', 'pgoutput');` |
| `slot "<s>" exists in another database, not "<db>"` | Slot created while connected to another database | Drop it (with the user's yes) and create it in `<db>`. |
| `only logical slots are supported: physical` | A physical slot has that name | Use a logical `pgoutput` slot with another name. |
| `publication "<p>" does not exist; please create it with: CREATE PUBLICATION ...` | No publication | Create it in the same database. |
| `publication "<p>" exists but contains no tables` | Empty publication | `ALTER PUBLICATION <p> ADD TABLE <schema>.<table>;` |
| `the following tables are selected in streams.json but are NOT tracked by publication "<p>"` | Stream not in publication | Run the `ALTER PUBLICATION` statement the error prints. |
| `lsn mismatch, please proceed with clear destination. lsn saved in state [<a>] current lsn [<b>]` | Slot position differs from `state.json`: slot recreated, shared, or advanced elsewhere | With the user's yes: `clear-destination`, then sync without `--state`. Use one slot per job. |
| `lsn is empty, please proceed with clear destination` | `state.json` has no LSN for a CDC run | Same as above. |
| `LSN not updated after 5 minutes` | `wal_sender_timeout` dropped the connection during a long run | `wal_sender_timeout = 0`. |
| `no records found in given initial wait time, try increasing it or do full load` | Postgres took longer than `initial_wait_time` to send the first change (large WAL backlog to decode) | Raise `update_method.initial_wait_time` (600–3600). |
| `replication slot "<s>" is active for PID <n>` (`55006`) | Another process (a second job, a stuck run) holds the slot | Stop the other consumer; never run two syncs of one job at once. |
| `could not access file "pgoutput"` | Postgres older than 10, or logical replication off (RDS) | Upgrade, or set `rds.logical_replication = 1`. |
| `cannot update table "<t>" because it does not have a replica identity and publishes updates` (on the **source** app) | Table without primary key added to the publication | `ALTER TABLE <t> REPLICA IDENTITY FULL;` |

## Data looks wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| Sync succeeds with 0 rows | Row-level security hides rows from the user | `ALTER USER <user> WITH BYPASSRLS;` or a policy for it. |
| Deleted rows have null columns except the key | Default replica identity sends only the key | `REPLICA IDENTITY FULL` on the table. |
| A `TRUNCATE` on the source left rows on the destination | `TRUNCATE` is not replicated | With the user's yes, `clear-destination` for the stream and sync again. |
| A large text/json column turns null after an update of another column | TOAST values not in WAL | `REPLICA IDENTITY FULL` on the table. |
| `numeric` values lose precision | `numeric` / `decimal` map to `Float64` | Expected at this version: [type-mapping.md](type-mapping.md). Cast in the query engine. |
| `time`, `interval`, `money` arrive as strings | Mapped to `String` | Expected: [type-mapping.md](type-mapping.md). |
| Incremental misses rows | `cursor_field` not always updated, or moves backwards | Pick a column maintained on every write, or use CDC. |

## SQLSTATE quick map

The driver classifies errors by SQLSTATE: `28P01`/`28000` auth, `3D000`/`3F000`/`42P01`/`42703` missing
object, `42501` permission, `53xxx` resources, `55006`/`55P03`/`40001`/`40P01` contention (a retry usually
clears it), `08xxx`/`57P01`/`57P03` network or server restart. `42601`, `42883` and other OLake-generated
SQL errors are OLake bugs: collect the log and report them.

Not listed: collect the log ([`olake-troubleshoot`](../../../olake-troubleshoot/SKILL.md)) and ask on the
[OLake Slack](https://olake.io/slack).
