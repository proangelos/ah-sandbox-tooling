#!/usr/bin/env bash
# Create a new numbered sandbox: a git worktree of each base repo (plus any
# optional repos named in WITH), each on its own sandbox/<n>/<repo> branch.
#
# Usage:
#   ./create.sh                                          # base repos only
#   WITH="cms-api tango-service" ./create.sh             # base + optional repos
#   PUSH_AS=fix-auth-bug ./create.sh                        # also wire up remote tracking
#
# PUSH_AS sets each repo's sandbox/<n>/<repo> branch to track origin/<PUSH_AS>, so a
# bare `git push` from inside that worktree pushes straight to <PUSH_AS> on the
# remote -- no -u, no explicit refspec. This only affects that one worktree's
# push behavior (via `git config --worktree`), not the source repo's main
# checkout or any other worktree.
#
# Each worktree branches off a fresh `git fetch origin <branch>` of that repo's
# source branch (DEFAULT_BRANCH, or its entry in BRANCH_OVERRIDES -- see
# repos.sh), so sandboxes always start from the latest remote state regardless
# of what the source repo's own working tree happens to be checked out to.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/repos.sh"

usage() {
  echo "Usage: WITH=\"repo1 repo2\" $0" >&2
  echo "  Base repos (always included): ${BASE_REPOS[*]}" >&2
  echo "  Optional repos (via WITH):    ${OPTIONAL_REPOS[*]}" >&2
  exit 1
}

# ---- pick the next sandbox number ----
next=1
for d in "$SANDBOX_ROOT"/*/; do
  [[ -d "$d" ]] || continue
  name="$(basename "$d")"
  [[ "$name" =~ ^[0-9]+$ ]] || continue
  (( 10#$name >= next )) && next=$(( 10#$name + 1 ))
done

sandbox_dir="$SANDBOX_ROOT/$next"

# ---- resolve repo list: base + WITH, deduped, order preserved ----
declare -A seen=()
requested=()
for r in "${BASE_REPOS[@]}" ${WITH:-}; do
  [[ -n "${seen[$r]:-}" ]] && continue
  if [[ -z "${REPOS[$r]:-}" ]]; then
    echo "error: unknown repo '$r' (not in repos.sh REPOS map)" >&2
    usage
  fi
  seen[$r]=1
  requested+=("$r")
done

echo "Creating sandbox $next at $sandbox_dir"
mkdir -p "$sandbox_dir"

for repo in "${requested[@]}"; do
  src="${REPOS[$repo]}"
  if [[ ! -d "$src/.git" ]]; then
    echo "error: $repo source not found or not a git repo at $src" >&2
    exit 1
  fi
  branch="sandbox/$next/$repo"
  dest="$sandbox_dir/$repo"
  source_branch="${BRANCH_OVERRIDES[$repo]:-$DEFAULT_BRANCH}"

  echo "  worktree: $repo  ($src -> $dest, branch $branch off origin/$source_branch)"
  if ! git -C "$src" fetch --quiet origin "$source_branch"; then
    echo "error: failed to fetch '$source_branch' from origin for $repo" >&2
    exit 1
  fi
  # --no-track: without it, git's branch.autoSetupMerge default would make this
  # branch track origin/$source_branch (e.g. master) just for having been
  # created from it -- a live wire if anything ever pushes to "@{upstream}"
  # without PUSH_AS deliberately having set tracking below.
  git -C "$src" worktree add -q -b "$branch" --no-track "$dest" "origin/$source_branch"

  if [[ -n "${PUSH_AS:-}" ]]; then
    # Enable per-worktree config once per source repo (harmless, repo-wide flag
    # that just permits the --worktree scope below to exist; changes no behavior
    # on its own).
    git -C "$src" config extensions.worktreeConfig true
    # Scoped to this worktree only: lets a same-name-mismatched upstream push
    # with a bare `git push`, without changing push.default for the main
    # checkout or any other worktree of $src.
    git -C "$dest" config --worktree push.default upstream
    # Branch tracking config lives in the shared repo config (branches are a
    # shared, exclusively-checked-out resource), same as any real feature branch.
    git -C "$src" config "branch.$branch.remote" origin
    git -C "$src" config "branch.$branch.merge" "refs/heads/$PUSH_AS"
    echo "    tracking: git push (bare) in $dest -> origin/$PUSH_AS"
  fi
done

echo
echo "Sandbox $next ready: $sandbox_dir"
echo "Repos: ${requested[*]}"
