#!/bin/bash
# Deploy gate for the OLake compose stack: wait until every service is ready, log in, and show the images in use.
# Reads the services from the running project itself, so it needs no list of service names.
#
# Usage: compose-gate.sh <project> <run-dir> [timeout-seconds] [ui-url]
#   project          the stack's compose project, olake-dev-<run-id>
#   run-dir          the login cookie jar is written to <run-dir>/cookies.txt
#   timeout-seconds  default 180: the "stack up" limit in the skill's Waits table
#   ui-url           default http://localhost:8000
#
# Ready means: a service with a healthcheck is healthy, a one-shot service (migration, signup-init) exited 0,
# and every other service is running. Then POST /login with the default admin login must return 200.
# It stops at the first broken state instead of waiting out the timeout: a one-shot that stays failed or a service
# that stays unhealthy across two polls, or a long-running service (restart always or unless-stopped) restarted twice
# during the gate. Long-running services start behind service_healthy conditions, so a normal start never restarts one.
# Prints one line per poll while waiting, then one line per service, the login result and the images,
# and ends with "GATE PASS" (exit 0) or "GATE FAIL: <reason>" (exit 1). Exit 2 on bad input.
set -u

project=${1:-}
run_dir=${2:-}
timeout=${3:-180}
url=${4:-http://localhost:8000}
[ -n "$project" ] && [ -d "$run_dir" ] || { echo "usage: compose-gate.sh <project> <run-dir> [timeout-seconds] [ui-url]" >&2; exit 2; }

poll=10 # seconds between checks: compose health checks run every 10 to 30 seconds, so faster polling adds nothing
deadline=$(( $(date +%s) + timeout ))
failed_before=""

# "|" separates the fields: with a tab, read would merge the empty Health field of a service without a healthcheck.
services() { docker compose -p "$project" ps -a --format '{{.Service}}|{{.State}}|{{.Health}}|{{.ExitCode}}' 2> /dev/null; }
# "<service>|<restart count>" for each long-running service; one-shots retry by design (on-failure) and are left out.
restarts() {
  docker inspect --format '{{index .Config.Labels "com.docker.compose.service"}}|{{.RestartCount}}|{{.HostConfig.RestartPolicy.Name}}' \
    $(docker compose -p "$project" ps -aq 2> /dev/null) 2> /dev/null | awk -F'|' '$3 == "always" || $3 == "unless-stopped" { print $1 "|" $2 }'
}
restarts_at_start=$(restarts)

while :; do
  rows=$(services)
  [ -n "$rows" ] || { echo "GATE FAIL: compose project '$project' has no containers"; exit 1; }
  waiting=""
  failed=""
  while IFS='|' read -r svc state health code; do
    case "$state/$health" in
      running/healthy | running/) ;;                      # ready; no healthcheck means running is enough
      exited/*) [ "$code" = 0 ] || failed="$failed $svc(exit=$code)" ;;
      running/unhealthy) failed="$failed $svc(unhealthy)" ;;
      *) waiting="$waiting $svc($state${health:+/$health})" ;; # created, restarting, starting, unhealthy
    esac
  done <<< "$rows"
  # A crash loop: the restart count only grows, so one poll is enough evidence.
  crashed=$(restarts | while IFS='|' read -r svc n; do
    before=$(printf '%s\n' "$restarts_at_start" | awk -F'|' -v s="$svc" '$1 == s { print $2 }')
    [ $(( n - ${before:-0} )) -ge 2 ] && printf ' %s(restarted %s times)' "$svc" $(( n - ${before:-0} ))
  done)
  if [ -n "$crashed" ]; then
    printf '%s\n' "$rows" | awk -F'|' '{ printf "%s %s %s exit=%s\n", $1, $2, ($3 == "" ? "-" : $3), $4 }'
    echo "GATE FAIL: crash loop:$crashed"
    exit 1
  fi
  # A one-shot with "restart: on-failure" shows a non-zero exit between retries, and a health check can fail once
  # while a service starts: fail only when the same state stays across two polls.
  if [ -n "$failed" ] && [ "$failed" = "$failed_before" ]; then
    printf '%s\n' "$rows" | awk -F'|' '{ printf "%s %s %s exit=%s\n", $1, $2, ($3 == "" ? "-" : $3), $4 }'
    echo "GATE FAIL: failed:$failed"
    exit 1
  fi
  failed_before=$failed
  [ -z "$waiting$failed" ] && break
  if [ "$(date +%s)" -ge "$deadline" ]; then
    printf '%s\n' "$rows" | awk -F'|' '{ printf "%s %s %s exit=%s\n", $1, $2, ($3 == "" ? "-" : $3), $4 }'
    echo "GATE FAIL: not ready after ${timeout}s:$waiting$failed"
    exit 1
  fi
  echo "waiting:$waiting$failed"
  sleep "$poll"
done

printf '%s\n' "$rows" | awk -F'|' '{ printf "%s %s %s exit=%s\n", $1, $2, ($3 == "" ? "-" : $3), $4 }'

# Healthy does not always mean serving: the login is the real readiness check, and its cookie is reused later.
code=000
while :; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -c "$run_dir/cookies.txt" -H 'Content-Type: application/json' \
    -d '{"username":"admin","password":"password"}' "$url/login" || true)
  [ "$code" = 200 ] && break
  [ "$(date +%s)" -ge "$deadline" ] && { echo "GATE FAIL: POST $url/login returned $code"; exit 1; }
  sleep "$poll"
done
echo "login=200 cookies=$run_dir/cookies.txt"

for c in olake-ui olake-temporal-worker; do
  img=$(docker inspect --format '{{.Config.Image}}' "$c" 2> /dev/null) || img=missing
  echo "image $c=$img"
done
echo "GATE PASS"
