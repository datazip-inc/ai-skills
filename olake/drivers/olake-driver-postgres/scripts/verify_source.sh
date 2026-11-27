#!/usr/bin/env bash
# Read-only checks that a Postgres source is ready for OLake. Runs only SELECT / SHOW.
#
# Connection: the standard libpq variables PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD (PGSSLMODE optional).
# Optional:
#   OLAKE_SCHEMAS      comma-separated schemas to sync (default: every non-system schema)
#   OLAKE_SLOT         replication slot from source.json; set it to run the CDC checks
#   OLAKE_PUBLICATION  publication from source.json
#   PSQL_DOCKER_NETWORK  docker network for the psql container when psql is not installed (default: host)
#
# Prints PASS / WARN / FAIL per check and exits 1 if any check fails. Never prints PGPASSWORD.

set -uo pipefail

: "${PGHOST:?set PGHOST}" "${PGDATABASE:?set PGDATABASE}" "${PGUSER:?set PGUSER}"
export PGPORT="${PGPORT:-5432}"
SCHEMAS="${OLAKE_SCHEMAS:-}"
SLOT="${OLAKE_SLOT:-}"
PUB="${OLAKE_PUBLICATION:-}"
failures=0

if command -v psql >/dev/null 2>&1; then
  PSQL=(psql)
else
  PSQL=(docker run --rm -i --network "${PSQL_DOCKER_NETWORK:-host}"
    -e PGHOST -e PGPORT -e PGDATABASE -e PGUSER -e PGPASSWORD -e PGSSLMODE
    postgres:16-alpine psql)
fi

# q <sql>: one value per line, no headers. For statements without variables.
q() { "${PSQL[@]}" -X -A -t -q -v ON_ERROR_STOP=1 -c "$1" 2>&1; }

pass() { printf 'PASS  %s\n' "$1"; }
warn() { printf 'WARN  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }

# Schemas in scope, as a SQL predicate on a namespace name column.
in_scope() {
  if [[ -n "$SCHEMAS" ]]; then
    printf "%s = ANY(string_to_array(replace(:'schemas', ' ', ''), ','))" "$1"
  else
    printf "%s NOT IN ('pg_catalog','information_schema') AND %s NOT LIKE 'pg\\_%%'" "$1" "$1"
  fi
}

# qv <sql>: same, for statements using :'schemas' :'slot' :'pub'. psql -c does not expand
# variables, so the statement goes on stdin; values pass through -v and are never spliced into SQL.
qv() { printf '%s\n' "$1" | "${PSQL[@]}" -X -A -t -q -v ON_ERROR_STOP=1 \
  -v schemas="$SCHEMAS" -v slot="$SLOT" -v pub="$PUB" 2>&1; }

# 1. Connection and version
version=$(q "SHOW server_version_num") || { fail "connect to $PGHOST:$PGPORT/$PGDATABASE as $PGUSER: $version"; exit 1; }
if (( version >= 100000 )); then pass "connected, server_version_num=$version"; else fail "Postgres $version is older than 10"; fi

# 2. Read access
tables=$(qv "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind IN ('r','p') AND NOT c.relispartition AND $(in_scope n.nspname);")
denied=$(qv "SELECT string_agg(n.nspname || '.' || c.relname, ', ') FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind IN ('r','p') AND NOT c.relispartition AND $(in_scope n.nspname)
  AND NOT (has_schema_privilege(n.oid, 'USAGE') AND has_table_privilege(c.oid, 'SELECT'));")
if [[ "$tables" == "0" ]]; then fail "no tables found in scope (OLAKE_SCHEMAS='${SCHEMAS}')"
elif [[ -n "$denied" ]]; then fail "no USAGE/SELECT on: $denied"
else pass "SELECT on all $tables tables in scope"; fi

rls=$(qv "SELECT string_agg(n.nspname || '.' || c.relname, ', ') FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relrowsecurity AND $(in_scope n.nspname)
  AND NOT (SELECT rolbypassrls OR rolsuper FROM pg_roles WHERE rolname = current_user);")
[[ -n "$rls" ]] && warn "row-level security may hide rows on: $rls (ALTER USER $PGUSER WITH BYPASSRLS)"

if [[ -z "$SLOT" ]]; then
  echo "INFO  OLAKE_SLOT not set: skipped CDC checks (Standalone mode)"
  exit $(( failures > 0 ))
fi

# 3. CDC server settings
wal=$(q "SHOW wal_level")
[[ "$wal" == "logical" ]] && pass "wal_level=logical" || fail "wal_level=$wal, needs logical (restart required)"

repl=$(q "SELECT rolsuper OR rolreplication OR CASE WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rds_replication')
  THEN pg_has_role(current_user, 'rds_replication', 'member') ELSE false END FROM pg_roles WHERE rolname = current_user")
[[ "$repl" == "t" ]] && pass "replication privilege" || fail "user $PGUSER lacks REPLICATION (RDS/Aurora: rds_replication)"

timeout=$(q "SELECT setting FROM pg_settings WHERE name = 'wal_sender_timeout'")
[[ "$timeout" == "0" ]] && pass "wal_sender_timeout=0" || warn "wal_sender_timeout=${timeout}ms; set 0 to avoid 'LSN not updated after 5 minutes'"

# 4. Slot
slot=$(qv "SELECT plugin || '|' || slot_type || '|' || coalesce(database, '') || '|' || active
  FROM pg_replication_slots WHERE slot_name = :'slot';")
if [[ -z "$slot" ]]; then
  fail "slot '$SLOT' not found: SELECT pg_create_logical_replication_slot('$SLOT', 'pgoutput');"
else
  IFS='|' read -r plugin stype sdb active <<<"$slot"
  if [[ "$stype" != "logical" ]]; then fail "slot '$SLOT' is $stype, needs logical"
  elif [[ "$plugin" != "pgoutput" ]]; then fail "slot '$SLOT' uses plugin $plugin, needs pgoutput"
  elif [[ "$sdb" != "$PGDATABASE" ]]; then fail "slot '$SLOT' belongs to database $sdb, not $PGDATABASE"
  else pass "slot '$SLOT' (pgoutput, $PGDATABASE)"; fi
  [[ "$active" == "true" ]] && warn "slot '$SLOT' is active now: another consumer may hold it"
fi

# 5. Publication
if [[ -z "$PUB" ]]; then
  fail "OLAKE_PUBLICATION not set; CDC needs a publication"
else
  pubinfo=$(qv "SELECT puballtables || '|' || pubviaroot FROM pg_publication WHERE pubname = :'pub';")
  if [[ -z "$pubinfo" ]]; then
    fail "publication '$PUB' not found: CREATE PUBLICATION $PUB FOR TABLE <schema>.<table>;"
  else
    IFS='|' read -r alltables viaroot <<<"$pubinfo"
    pass "publication '$PUB' exists"
    if [[ "$alltables" != "true" ]]; then
      missing=$(qv "SELECT string_agg(n.nspname || '.' || c.relname, ', ') FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relkind IN ('r','p') AND NOT c.relispartition AND $(in_scope n.nspname)
        AND NOT EXISTS (SELECT 1 FROM pg_publication_tables t WHERE t.pubname = :'pub' AND t.schemaname = n.nspname AND t.tablename = c.relname);")
      [[ -n "$missing" ]] && warn "not in publication (sync fails if selected): $missing"
    fi
    partitioned=$(qv "SELECT string_agg(n.nspname || '.' || c.relname, ', ') FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE c.relkind = 'p' AND NOT c.relispartition AND $(in_scope n.nspname)
      AND ((SELECT puballtables FROM pg_publication WHERE pubname = :'pub')
        OR EXISTS (SELECT 1 FROM pg_publication_rel r JOIN pg_publication p ON p.oid = r.prpubid
                   WHERE p.pubname = :'pub' AND r.prrelid = c.oid));")
    if [[ -n "$partitioned" && "$viaroot" != "true" ]]; then
      fail "partitioned table(s) $partitioned published with publish_via_partition_root=false: ALTER PUBLICATION $PUB SET (publish_via_partition_root = true);"
    fi
  fi
fi

# 6. Replica identity
noident=$(qv "SELECT string_agg(n.nspname || '.' || c.relname, ', ') FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind = 'r' AND NOT c.relispartition AND $(in_scope n.nspname)
  AND (c.relreplident = 'n' OR (c.relreplident = 'd' AND NOT EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid = c.oid AND i.indisprimary)));")
[[ -n "$noident" ]] && warn "no replica identity; once in the publication, UPDATE/DELETE on them fail on the source: $noident -> ALTER TABLE <t> REPLICA IDENTITY FULL;"
notfull=$(qv "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind = 'r' AND $(in_scope n.nspname) AND c.relreplident <> 'f';")
[[ "$notfull" != "0" ]] && warn "$notfull table(s) without REPLICA IDENTITY FULL: deletes keep only the key, unchanged TOAST columns arrive null"

exit $(( failures > 0 ))
