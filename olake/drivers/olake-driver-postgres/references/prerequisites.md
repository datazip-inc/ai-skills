# Postgres prerequisites

Sources: [`drivers/postgres/internal/prerequisites.go`](https://github.com/datazip-inc/olake/blob/v1.1.2/drivers/postgres/internal/prerequisites.go),
[generic setup guide](https://olake.io/docs/connectors/postgres/setup/generic).
Managed hosts set some of these differently: [cloud-variants.md](cloud-variants.md).

Replace `olake_user`, `shop`, `public`, `olake_pub` and `olake_slot` with the real names.

## Read access

Needed for every mode.

```sql
CREATE USER olake_user WITH PASSWORD '<PASSWORD>';
GRANT CONNECT ON DATABASE shop TO olake_user;
-- Repeat per schema to sync
GRANT USAGE ON SCHEMA public TO olake_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO olake_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO olake_user;
```

- The host must accept OLake's IP: a `pg_hba.conf` line (self-hosted), or a firewall / security group
  rule (cloud).
- Row-level security filters rows silently: the sync succeeds with fewer or zero rows. Give the user
  `BYPASSRLS` or a policy that shows every row: `ALTER USER olake_user WITH BYPASSRLS;`

## CDC

OLake reads changes through a logical replication slot with the built-in `pgoutput` plugin. The
`wal2json` plugin is deprecated.

`check` and sync setup run these checks ([abstract prerequisites](../../olake-driver-abstract/references/prerequisites.md)):

| Check | Required | Passes when | Fix |
| --- | --- | --- | --- |
| `wal_level` | yes | `SHOW wal_level` is `logical` | Set `wal_level = logical`, restart. |
| `replication_privilege` | yes | User is superuser, has `REPLICATION`, or is a member of `rds_replication` | `ALTER ROLE olake_user WITH REPLICATION;` (RDS/Aurora: `GRANT rds_replication TO olake_user;`) |
| `replication_slot` | yes | Slot exists, is `logical`, and belongs to the configured `database` | Create it in that database (below). |
| `publication` | yes | Publication exists | Create it (below). |
| `wal_sender_timeout` | no | Value is `0` | `ALTER SYSTEM SET wal_sender_timeout = 0; SELECT pg_reload_conf();` |

### 1. Server settings

`postgresql.conf` (or `ALTER SYSTEM SET ...`). `wal_level` needs a restart; confirm with the user.

```conf
wal_level = logical
max_replication_slots = 10     # at least one per OLake job, plus other consumers
max_wal_senders = 10           # more than max_replication_slots
wal_sender_timeout = 0         # else long syncs fail with "LSN not updated after 5 minutes"
max_slot_wal_keep_size = 10GB  # optional, Postgres 13+: caps WAL kept for a stalled slot
```

`pg_hba.conf` needs a replication line for OLake's IP as well as the normal one:

```conf
hostssl all          olake_user  <OLAKE_IP>/32  scram-sha-256
hostssl replication  olake_user  <OLAKE_IP>/32  scram-sha-256
```

### 2. Replication privilege

```sql
ALTER ROLE olake_user WITH REPLICATION;
```

### 3. Replica identity

A table in a publication needs a replica identity, or Postgres **rejects** `UPDATE` and `DELETE` on it
(`cannot update table "<t>" because it does not have a replica identity and publishes updates`).

| Table | Set |
| --- | --- |
| Has a primary key | `DEFAULT` (nothing to do). Deletes then carry only the key: other columns are null on the destination. |
| No primary key, or full rows wanted on deletes and TOAST updates | `ALTER TABLE <schema>.<table> REPLICA IDENTITY FULL;` (more WAL) |

### 4. Publication

Create the publication before the slot, in the database OLake connects to.

```sql
CREATE PUBLICATION olake_pub FOR TABLE public.orders, public.customers;
-- or every table in a schema (Postgres 15+):  CREATE PUBLICATION olake_pub FOR TABLES IN SCHEMA public;
-- or every table:                              CREATE PUBLICATION olake_pub FOR ALL TABLES;

-- Required when any synced table is partitioned (Postgres 13+)
ALTER PUBLICATION olake_pub SET (publish_via_partition_root = true);

-- Add a table later
ALTER PUBLICATION olake_pub ADD TABLE public.payments;
```

Creating a publication needs table ownership (or superuser for `FOR ALL TABLES`). The sync fails if a
selected stream is not in the publication.

### 5. Replication slot

```sql
SELECT pg_create_logical_replication_slot('olake_slot', 'pgoutput');
```

- One slot per OLake job. Two jobs on one slot each miss changes the other consumed.
- Slot names: lower case, digits, `_`. A slot keeps WAL until OLake reads it: schedule syncs often
  enough, and drop the slot of a deleted job (`SELECT pg_drop_replication_slot('olake_slot');`, only with
  the user's yes).

### 6. Check it

```sql
SHOW wal_level;
SELECT rolreplication FROM pg_roles WHERE rolname = current_user;
SELECT slot_name, plugin, slot_type, database, active FROM pg_replication_slots WHERE slot_name = 'olake_slot';
SELECT pubname, pubviaroot FROM pg_publication WHERE pubname = 'olake_pub';
SELECT schemaname, tablename FROM pg_publication_tables WHERE pubname = 'olake_pub';
```

Or run [`scripts/verify_source.sh`](../scripts/verify_source.sh), which runs these and more.

## Read replicas

- Postgres 15 and older: a standby cannot be a logical replication publisher. Point CDC at the primary.
- Postgres 16+: logical decoding on a standby works, but `wal_level=logical` must be set on the primary
  too, and the slot is lost on failover. Prefer the primary for CDC.
- `full_refresh` and `incremental` work against any replica.
