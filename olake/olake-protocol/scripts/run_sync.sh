#!/usr/bin/env bash
# Run the OLake CLI path for one source and print a short summary per stage.
# Full logs stay in the config folder; only the deciding lines are printed.
#
# Usage: run_sync.sh <source> <CONFIG_DIR> [options]
#   <source>       postgres mysql mongodb mssql oracle db2 s3 kafka
#   <CONFIG_DIR>   folder with source.json and destination.json
# Options:
#   --tag <tag>        image tag (default: $OLAKE_TAG, else olake/OLAKE_VERSION)
#   --network <name>   docker network, e.g. olake-poc for the local Iceberg stack
#   --stages <list>    comma-separated, default check,discover,sync
#                      (check = check-source,check-destination)
#   --state            pass --state state.json to sync (rerun of incremental or cdc streams)
#
# Exit code: 0 when every stage passed, 1 on the first failed stage.
set -uo pipefail

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[[ $# -lt 2 ]] && usage

SOURCE=$1
DIR=$(cd "$2" 2>/dev/null && pwd) || { echo "config folder not found: $2"; exit 2; }
shift 2
VERSION_FILE="$(dirname "$0")/../../OLAKE_VERSION"
TAG=${OLAKE_TAG:-$(cat "$VERSION_FILE" 2>/dev/null)}
NETWORK=""
STAGES="check,discover,sync"
STATE=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --tag) TAG=$2; shift 2 ;;
    --network) NETWORK=$2; shift 2 ;;
    --stages) STAGES=$2; shift 2 ;;
    --state) STATE=1; shift ;;
    *) usage ;;
  esac
done

[[ -z $TAG ]] && { echo "no image tag: pass --tag, set OLAKE_TAG, or restore $VERSION_FILE"; exit 2; }
IMAGE=olakego/source-$SOURCE:$TAG
RUN=(docker run --rm -v "$DIR:/mnt/config")
[[ -n $NETWORK ]] && RUN+=(--network "$NETWORK")
RUN+=("$IMAGE")
TRIAGE="$(cd "$(dirname "$0")/../.." && pwd)/olake-troubleshoot/scripts/triage_logs.py"

fail() {
  echo "FAILED at $1. Full log: $2"
  if [[ -f $TRIAGE ]] && command -v python3 >/dev/null; then
    python3 "$TRIAGE" "$2"
  else
    grep -i -E 'fatal|error' "$2" | tail -3 | cut -c1-300
  fi
  exit 1
}

# check prints a connectionStatus message; anything but SUCCEEDED is a failure.
check() {
  local name=$1 log="$DIR/$1.log"; shift
  "${RUN[@]}" check "$@" >"$log" 2>&1
  local status
  status=$(grep -o '"status":"[A-Z]*"' "$log" | tail -1 | cut -d'"' -f4)
  if [[ $status == SUCCEEDED ]]; then echo "ok   $name"; else fail "$name (${status:-no status})" "$log"; fi
}

for stage in ${STAGES//,/ }; do
  case $stage in
    check|check-source|check-destination)
      if [[ $stage != check-destination ]]; then
        [[ -f $DIR/source.json ]] || { echo "missing $DIR/source.json"; exit 2; }
        check check-source --config /mnt/config/source.json
      fi
      if [[ $stage != check-source ]]; then
        [[ -f $DIR/destination.json ]] || { echo "missing $DIR/destination.json"; exit 2; }
        check check-destination --destination /mnt/config/destination.json
      fi
      ;;
    discover)
      log="$DIR/discover.log"
      "${RUN[@]}" discover --config /mnt/config/source.json --destination /mnt/config/destination.json >"$log" 2>&1 \
        && [[ -f $DIR/selected_streams.json ]] || fail discover "$log"
      echo "ok   discover"
      python3 - "$DIR/selected_streams.json" <<'PY' 2>/dev/null || true
import json, sys
streams = json.load(open(sys.argv[1]))["selected_streams"]
items = [(ns, s) for ns, ss in streams.items() for s in ss]
print(f"     {len(items)} stream(s) selected:")
for ns, s in items[:20]:
    print(f"     {ns}.{s.get('stream_name')}  {s.get('sync_mode', '')}  normalization={s.get('normalization', False)}")
if len(items) > 20:
    print(f"     ... {len(items) - 20} more")
PY
      ;;
    sync)
      log="$DIR/sync.log"
      args=(sync --config /mnt/config/source.json --destination /mnt/config/destination.json
        --available-streams /mnt/config/available_streams.json --selected-streams /mnt/config/selected_streams.json)
      [[ -n $STATE ]] && args+=(--state /mnt/config/state.json)
      "${RUN[@]}" "${args[@]}" >"$log" 2>&1 || fail sync "$log"
      grep -q -i -E '"level":"fatal"|\bFATAL\b' "$log" && fail sync "$log"
      echo "ok   sync"
      records=$(grep -o 'Total records read: [^|"]*' "$log" | tail -1)
      echo "     ${records:-Total records read: not logged}"
      [[ -f $DIR/stats.json ]] && python3 - "$DIR/stats.json" <<'PY' 2>/dev/null || true
import json, sys
s = json.load(open(sys.argv[1]))
print(f"     stats.json: Synced Records {s.get('Synced Records')}, {s.get('Seconds Elapsed')} s")
PY
      [[ -f $DIR/state.json ]] && echo "     state.json written (rerun with --state)"
      ;;
    *) echo "unknown stage: $stage"; exit 2 ;;
  esac
done
