#!/bin/bash
# Deploy gate for the OLake chart on kind: wait until every workload is ready, and stop at the first broken state
# instead of waiting out the timeout. Reads the workloads from the namespace itself, so it needs no list of names.
#
# Usage: kind-gate.sh <kubeconfig> [namespace] [timeout-seconds]
#   kubeconfig       the stack's own kubeconfig, <run-dir>/kubeconfig (never the user's ~/.kube/config)
#   namespace        default olake
#   timeout-seconds  default 300: a first install takes about 2 minutes with the images loaded
#
# Ready means: every Deployment and StatefulSet finished its rollout with all replicas ready, and every Job succeeded.
# Run it after the change is applied (helm install started, or helm upgrade returned), so it sees the new spec.
# Broken means, seen in two polls in a row: a container that crashed (CrashLoopBackOff, or terminated with Error or
# OOMKilled, outside a Job), an image that cannot be pulled or used, a pod that cannot be scheduled, or a Job marked
# Failed. Two polls, so a state that clears by itself does not fail the gate. The chart's init containers wait for
# their dependencies, so a normal install never crashes a container.
# Prints one line per poll while waiting, and ends with "GATE PASS" (exit 0), or "GATE FAIL: <reason>" with the
# workloads and the latest warning events (exit 1). Exit 2 on bad input.
set -u

kubeconfig=${1:-}
ns=${2:-olake}
timeout=${3:-300}
[ -f "$kubeconfig" ] || { echo "usage: kind-gate.sh <kubeconfig> [namespace] [timeout-seconds]" >&2; exit 2; }

poll=10 # seconds between checks: pod states change on the kubelet's sync, so faster polling adds nothing
deadline=$(( $(date +%s) + timeout ))
broken_before=""

k() { kubectl --kubeconfig "$kubeconfig" -n "$ns" "$@"; }

workloads() {
  # Ready only when the rollout is done: the controller saw the newest spec, every replica runs it, and no old one is left.
  k get deploy,statefulset -o jsonpath='{range .items[*]}{.kind}/{.metadata.name}|{.spec.replicas}|{.status.readyReplicas}|{.status.updatedReplicas}|{.status.replicas}|{.metadata.generation}|{.status.observedGeneration}{"\n"}{end}' 2> /dev/null
}
jobs() {
  k get jobs -o jsonpath='{range .items[*]}{.metadata.name}|{.status.succeeded}|{.status.conditions[?(@.type=="Failed")].status}{"\n"}{end}' 2> /dev/null
}
pods() {
  k get pods -o jsonpath='{range .items[*]}{.metadata.name}|{.metadata.ownerReferences[0].kind}|{range .status.initContainerStatuses[*]}{.state.waiting.reason} {.state.terminated.reason} {end}{range .status.containerStatuses[*]}{.state.waiting.reason} {.state.terminated.reason} {end}|{.status.conditions[?(@.type=="PodScheduled")].reason}{"\n"}{end}' 2> /dev/null
}

report() {
  printf '%s\n' "$(workloads)" | awk -F'|' 'NF { printf "%s ready=%s/%s\n", $1, ($3 == "" ? 0 : $3), $2 }'
  printf '%s\n' "$(jobs)" | awk -F'|' 'NF { printf "job/%s succeeded=%s failed=%s\n", $1, ($2 == "" ? 0 : $2), ($3 == "" ? "-" : $3) }'
  k get events --sort-by=.lastTimestamp --field-selector type!=Normal 2> /dev/null | tail -10 | cut -c1-250
}

while :; do
  w=$(workloads)
  j=$(jobs)
  p=$(pods)
  waiting=""
  broken=""
  while IFS='|' read -r name want ready updated total gen seen; do
    [ -n "$name" ] || continue
    want=${want:-0}
    if [ "${ready:-0}" != "$want" ] || [ "${updated:-0}" != "$want" ] || [ "${total:-0}" != "$want" ] || [ "$gen" != "$seen" ]; then
      waiting="$waiting $name(${ready:-0}/$want)"
    fi
  done <<< "$w"
  while IFS='|' read -r name ok failed; do
    [ -n "$name" ] || continue
    if [ "$failed" = True ]; then broken="$broken job/$name(Failed)"
    elif [ -z "$ok" ]; then waiting="$waiting job/$name"; fi
  done <<< "$j"
  while IFS='|' read -r name owner reasons scheduled; do
    [ -n "$name" ] || continue
    state=""
    for r in $reasons; do
      case $r in
        # The pairs alternate between polls, so each pair counts as one state.
        ErrImagePull | ImagePullBackOff) state="ImagePull" ;;
        # A Job's pod may fail and retry; the Job's own Failed condition decides for it.
        CrashLoopBackOff | Error | OOMKilled) [ "$owner" = Job ] || state="Crash" ;;
        InvalidImageName | CreateContainerConfigError | CreateContainerError | RunContainerError) state=$r ;;
      esac
    done
    [ -n "$state" ] && broken="$broken pod/$name($state)"
    [ "$scheduled" = Unschedulable ] && broken="$broken pod/$name(Unschedulable)"
  done <<< "$p"

  if [ -n "$broken" ] && [ "$broken" = "$broken_before" ]; then
    report
    echo "GATE FAIL: broken:$broken"
    exit 1
  fi
  broken_before=$broken
  [ -n "$w" ] && [ -z "$waiting$broken" ] && break
  if [ "$(date +%s)" -ge "$deadline" ]; then
    report
    echo "GATE FAIL: not ready after ${timeout}s:${waiting:- no workloads in namespace $ns}$broken"
    exit 1
  fi
  echo "waiting:${waiting:- no workloads yet}$broken"
  sleep "$poll"
done

report | grep -v '^LAST SEEN' | grep -E 'ready=|^job/'
k get deploy -o jsonpath='{range .items[*]}image {.metadata.name}={.spec.template.spec.containers[0].image}{"\n"}{end}'
echo "GATE PASS"
