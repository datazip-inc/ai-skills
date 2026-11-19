#!/bin/bash
# Describe a git checkout for a test, and guard it around a build. Never changes the working tree.
#
# Usage:
#   checkout-info.sh <path> [base]              Print the facts a test records (base branch: staging)
#   checkout-info.sh --snapshot <path> <file>   Before a build: save every changed or untracked file with its content hash
#   checkout-info.sh --compare <path> <file>    After a build: print what the build changed, against the snapshot
#
# Default output, one key=value per line:
#   branch, sha (8 characters), base, behind, ahead, dirty (yes or no),
#   diff_hash (8 characters, uncommitted changes including untracked files; empty when clean),
#   run_tag (v100.0.0-test-<sha>[-dirty-<diff_hash>]), changed_files (count against the base),
#   then up to 30 "changed <file>" lines.
#
# --compare prints one line per file and exits 0:
#   REVERT <file>  clean before, changed now: the build did it; restore with `git -C <path> checkout -- <file>`
#   ASK <file>     already changed before, and changed again: holds the user's edits, so ask before touching it
#   NEW <file>     untracked and new since the snapshot: report it, do not delete it
#   CLEAN          nothing changed
set -u

die() { echo "error: $*" >&2; exit 2; }

# One line per changed or untracked file: "<sha256 or deleted><TAB><path>", sorted by path.
file_states() {
  local repo=$1 f
  {
    git -C "$repo" diff HEAD --name-only -z
    git -C "$repo" ls-files --others --exclude-standard -z
  } | sort -zu | while IFS= read -r -d '' f; do
    if [ -f "$repo/$f" ]; then
      printf '%s\t%s\n' "$(shasum -a 256 "$repo/$f" | cut -c1-64)" "$f"
    else
      printf 'deleted\t%s\n' "$f"
    fi
  done
}

case "${1:-}" in
  --snapshot)
    [ $# -eq 3 ] || die "usage: checkout-info.sh --snapshot <path> <file>"
    git -C "$2" rev-parse --git-dir > /dev/null 2>&1 || die "$2 is not a git checkout"
    file_states "$2" > "$3"
    echo "snapshot: $(wc -l < "$3" | tr -d ' ') changed or untracked file(s) saved to $3"
    exit 0
    ;;
  --compare)
    [ $# -eq 3 ] || die "usage: checkout-info.sh --compare <path> <file>"
    [ -f "$3" ] || die "no snapshot at $3"
    repo=$2
    now=$(mktemp)
    file_states "$repo" > "$now"
    found=0
    while IFS=$'\t' read -r hash f; do
      before_hash=$(awk -F'\t' -v f="$f" '$2 == f { print $1; exit }' "$3")
      if [ -z "$before_hash" ]; then
        if git -C "$repo" ls-files --error-unmatch -- "$f" > /dev/null 2>&1; then
          echo "REVERT $f"
        else
          echo "NEW $f"
        fi
        found=1
      elif [ "$before_hash" != "$hash" ]; then
        echo "ASK $f"
        found=1
      fi
    done < "$now"
    rm -f "$now"
    [ $found -eq 0 ] && echo "CLEAN"
    exit 0
    ;;
esac

[ $# -ge 1 ] || die "usage: checkout-info.sh <path> [base]"
repo=$1
base=${2:-staging}
git -C "$repo" rev-parse --git-dir > /dev/null 2>&1 || die "$repo is not a git checkout"

# Fetch only the base branch, so behind and ahead compare against today's base. Offline keeps the last fetched ref.
if ! git -C "$repo" fetch -q origin "$base" 2> /dev/null; then
  echo "warning=fetch of origin/$base failed; using the last fetched origin/$base"
fi
git -C "$repo" rev-parse -q --verify "origin/$base" > /dev/null || die "origin/$base does not exist in $repo"

sha=$(git -C "$repo" rev-parse --short=8 HEAD)
read -r behind ahead < <(git -C "$repo" rev-list --left-right --count "origin/$base...HEAD")
states=$(file_states "$repo")
if [ -n "$states" ]; then
  dirty=yes
  diff_hash=$({ git -C "$repo" diff HEAD --binary; printf '%s\n' "$states"; } | shasum -a 256 | cut -c1-8)
  run_tag="v100.0.0-test-$sha-dirty-$diff_hash"
else
  dirty=no
  diff_hash=
  run_tag="v100.0.0-test-$sha"
fi
changed=$(git -C "$repo" diff --name-only "origin/$base...HEAD")

echo "branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
echo "sha=$sha"
echo "base=origin/$base"
echo "behind=$behind"
echo "ahead=$ahead"
echo "dirty=$dirty"
echo "diff_hash=$diff_hash"
echo "run_tag=$run_tag"
echo "changed_files=$(printf '%s' "$changed" | grep -c . || true)"
printf '%s\n' "$changed" | grep . | head -30 | sed 's/^/changed /'
