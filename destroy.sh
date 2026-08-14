#!/usr/bin/env bash
# Tear down a numbered sandbox: remove each repo's worktree and its
# sandbox/<n>/<repo> branch from the source repo, then remove the sandbox dir.
# Matches by leading index regardless of an optional "-<title>" suffix on the
# dir name (e.g. "3" finds both "3/" and "3-docsTile/").
#
# Usage: ./destroy.sh <sandbox number>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/repos.sh"

n="${1:-}"
[[ "$n" =~ ^[0-9]+$ ]] || { echo "usage: $0 <sandbox number>" >&2; exit 1; }

sandbox_dir=""
for candidate in "$SANDBOX_ROOT/$n" "$SANDBOX_ROOT/$n"-*; do
  [[ -d "$candidate" ]] || continue
  base="$(basename "$candidate")"
  [[ "$base" =~ ^${n}(-.*)?$ ]] || continue
  sandbox_dir="$candidate"
  break
done
[[ -n "$sandbox_dir" ]] || { echo "error: no sandbox numbered $n under $SANDBOX_ROOT" >&2; exit 1; }

for dest in "$sandbox_dir"/*/; do
  [[ -d "$dest" ]] || continue
  repo="$(basename "$dest")"
  src="${REPOS[$repo]:-}"
  if [[ -z "$src" ]]; then
    echo "warning: '$repo' is not in repos.sh REPOS map, skipping (remove manually)" >&2
    continue
  fi
  branch="sandbox/$n/$repo"
  echo "removing worktree $repo"
  if ! git -C "$src" worktree remove --force "$dest" 2>/dev/null; then
    echo "  worktree remove failed for $repo -- leaving $dest in place, check for uncommitted work" >&2
    continue
  fi
  git -C "$src" branch -D "$branch" 2>/dev/null || true
done

if rmdir "$sandbox_dir" 2>/dev/null; then
  echo "sandbox $n destroyed"
else
  echo "note: $sandbox_dir not empty (some worktree removes may have failed) -- left in place"
fi
