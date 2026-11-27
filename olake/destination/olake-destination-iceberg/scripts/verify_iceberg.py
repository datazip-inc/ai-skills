#!/usr/bin/env python3
"""Read-only check of the Iceberg tables OLake wrote, through the REST catalog API.

Usage: python3 scripts/verify_iceberg.py <REST_CATALOG_URL> [NAMESPACE [TABLE]]
  python3 scripts/verify_iceberg.py http://localhost:8181                         # list namespaces
  python3 scripts/verify_iceberg.py http://localhost:8181 postgres_shop_public     # every table in it
  python3 scripts/verify_iceberg.py http://localhost:8181 postgres_shop_public orders

Prints, per table, the current snapshot's record and delete counts. Only GET requests; standard
library only. REST_TOKEN in the environment is sent as a bearer token and never printed.
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


def get(base, path):
    req = urllib.request.Request(base.rstrip("/") + "/v1/" + path)
    token = os.environ.get("REST_TOKEN")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def table_summary(base, namespace, table):
    meta = get(base, f"namespaces/{urllib.parse.quote(namespace)}/tables/{urllib.parse.quote(table)}")["metadata"]
    current = meta.get("current-snapshot-id")
    snapshot = next((s for s in meta.get("snapshots", []) if s["snapshot-id"] == current), None)
    if snapshot is None:
        return f"{namespace}.{table}: no snapshot yet (nothing committed)"
    s = snapshot["summary"]
    line = (f"{namespace}.{table}: records={s.get('total-records')} data_files={s.get('total-data-files')} "
            f"equality_deletes={s.get('total-equality-deletes', '0')} position_deletes={s.get('total-position-deletes', '0')} "
            f"last_operation={s.get('operation')}")
    if s.get("total-equality-deletes", "0") != "0" or s.get("total-position-deletes", "0") != "0":
        line += "\n  note: records counts rows in data files before deletes; count rows with a query engine"
    return line


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    base, args = sys.argv[1], sys.argv[2:]
    try:
        if not args:
            for ns in get(base, "namespaces")["namespaces"]:
                print(".".join(ns))
            return
        namespace = args[0]
        tables = args[1:] or [t["name"] for t in get(base, f"namespaces/{urllib.parse.quote(namespace)}/tables")["identifiers"]]
        if not tables:
            sys.exit(f"FAIL  no tables in namespace {namespace}")
        for table in tables:
            print(table_summary(base, namespace, table))
    except urllib.error.HTTPError as e:
        sys.exit(f"FAIL  {e.code} {e.reason}: {e.read().decode(errors='replace')[:300]}")
    except urllib.error.URLError as e:
        sys.exit(f"FAIL  cannot reach {base}: {e.reason}")


if __name__ == "__main__":
    main()
