#!/bin/bash
# Pick the release tag to pin for an image that the test does not build: the newest vX.Y.Z git tag of the
# image's repo whose image is published on Docker Hub. Needs network access to GitHub and Docker Hub.
#
# Usage: release-tag.sh <image>      for example olakego/source-postgres, olakego/ui, olakego/ui-worker
#
# Prints "tag=<tag>" and exits 0, after one "skipped=<tag> (not published)" line for each newer tag whose
# image is missing. Exits 1 when none of the newest tags is published, 2 on bad input or no network.
set -u

image=${1:-}
case $image in
  olakego/source-*) repo=olake ;;
  olakego/ui) repo=olake-ui ;;
  olakego/ui-worker | olakego/k8s-worker) repo=olake-helm ;; # olake-helm's olake-X.Y.Z tags are chart releases, not images
  *) echo "error: unknown image '$image'; expected olakego/source-<driver>, olakego/ui or olakego/ui-worker" >&2; exit 2 ;;
esac

# Release tags only: vX.Y.Z, no pre-release suffix. ls-remote needs no local clone.
tags=$(git ls-remote --tags --refs "https://github.com/datazip-inc/$repo.git" 'v*' 2> /dev/null \
  | sed 's#.*refs/tags/##' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -rV)
[ -n "$tags" ] || { echo "error: no release tags read from github.com/datazip-inc/$repo (network?)" >&2; exit 2; }

# A release is usually published within minutes of its tag; checking the newest 5 covers a slow or failed publish.
for tag in $(printf '%s\n' "$tags" | head -5); do
  if docker manifest inspect "$image:$tag" > /dev/null 2>&1; then
    echo "tag=$tag"
    exit 0
  fi
  echo "skipped=$tag (not published)"
done
echo "error: none of the 5 newest release tags of $repo is published as $image" >&2
exit 1
