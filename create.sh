#!/usr/bin/env bash
# Create a new numbered sandbox: a git worktree of each base repo (plus any
# optional repos named in WITH), each on its own sandbox/<n>/<repo> branch.
#
# Usage:
#   ./create.sh                                          # base repos only
#   WITH="cms-api tango-service" ./create.sh             # base + optional repos
#   TITLE=docsTile ./create.sh                           # dir is "<n>-docsTile" instead of just "<n>"
#   PUSH_AS=fix-auth-bug ./create.sh                        # also wire up remote tracking
#
# TITLE is cosmetic only -- branches, PUSH_AS tracking, and `destroy.sh <n>`
# all key off the leading number, never the title, so the sandbox stays
# referenceable by index alone (e.g. `make destroy N=3` finds "3-docsTile").
#
# PUSH_AS sets each repo's sandbox/<n>/<repo> branch to track origin/<PUSH_AS>, so a
# bare `git push` from inside that worktree pushes straight to <PUSH_AS> on the
# remote -- no -u, no explicit refspec. This only affects that one worktree's
# push behavior (via `git config --worktree`), not the source repo's main
# checkout or any other worktree.
#
# Each worktree branches off a fresh `git fetch origin <branch>` of that repo's
# source branch (its entry in SOURCE_BRANCHES -- see repos.sh), so sandboxes
# always start from the latest remote state regardless of what the source
# repo's own working tree happens to be checked out to.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/repos.sh"

usage() {
  echo "Usage: WITH=\"repo1 repo2\" $0" >&2
  echo "  Base repos (always included): ${BASE_REPOS[*]}" >&2
  echo "  Optional repos (via WITH):    ${OPTIONAL_REPOS[*]}" >&2
  exit 1
}

if [[ "${TITLE:-}" == */* ]]; then
  echo "error: TITLE cannot contain '/'" >&2
  exit 1
fi

# ---- pick the next sandbox number (dirs are "<n>" or "<n>-<title>") ----
next=1
for d in "$SANDBOX_ROOT"/*/; do
  [[ -d "$d" ]] || continue
  name="$(basename "$d")"
  [[ "$name" =~ ^([0-9]+)(-.*)?$ ]] || continue
  num="${BASH_REMATCH[1]}"
  (( 10#$num >= next )) && next=$(( 10#$num + 1 ))
done

sandbox_name="$next"
[[ -n "${TITLE:-}" ]] && sandbox_name="$next-$TITLE"
sandbox_dir="$SANDBOX_ROOT/$sandbox_name"

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

# ---- group requested repos by REPO_GROUP (repos.sh), preserving first-seen
# order, so the sandbox's own README can explain how they relate instead of
# just listing them flat.
group_order=()
declare -A group_seen=()
declare -A group_members=()
for repo in "${requested[@]}"; do
  g="${REPO_GROUP[$repo]:-$repo}"
  if [[ -z "${group_seen[$g]:-}" ]]; then
    group_seen[$g]=1
    group_order+=("$g")
  fi
  group_members[$g]+="$repo"$'\n'
done

# repo -> "branch X off origin/Y" line and repo -> raw branch name, filled in
# as each worktree is created below; assembled into the README after the loop.
declare -A repo_branch_line=()
declare -A repo_branch_name=()

for repo in "${requested[@]}"; do
  src="${REPOS[$repo]}"
  if [[ ! -d "$src/.git" ]]; then
    echo "error: $repo source not found or not a git repo at $src" >&2
    exit 1
  fi
  branch="sandbox/$next/$repo"
  dest="$sandbox_dir/$repo"
  source_branch="${SOURCE_BRANCHES[$repo]:-}"
  if [[ -z "$source_branch" ]]; then
    echo "error: no SOURCE_BRANCHES entry for '$repo' in repos.sh" >&2
    exit 1
  fi

  if ! git -C "$src" fetch --quiet origin "$source_branch" 2>/dev/null; then
    echo "error: failed to fetch '$source_branch' from origin for $repo" >&2
    exit 1
  fi

  echo "  worktree: $repo  ($src -> $dest, branch $branch off origin/$source_branch)"
  # --no-track: without it, git's branch.autoSetupMerge default would make this
  # branch track origin/$source_branch (e.g. master) just for having been
  # created from it -- a live wire if anything ever pushes to "@{upstream}"
  # without PUSH_AS deliberately having set tracking below.
  git -C "$src" worktree add -q -b "$branch" --no-track "$dest" "origin/$source_branch"
  repo_branch_line[$repo]="branch \`$branch\` off \`origin/$source_branch\`"
  repo_branch_name[$repo]="$branch"

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

# ---- assemble the grouped "## Repos" body: a header per group with >1
# requested member (to name the relationship), a plain bullet otherwise.
readme_repo_lines=""
for g in "${group_order[@]}"; do
  members=()
  while IFS= read -r m; do [[ -n "$m" ]] && members+=("$m"); done <<< "${group_members[$g]}"
  (( ${#members[@]} > 1 )) && readme_repo_lines+="**$g:**"$'\n'
  for m in "${members[@]}"; do
    desc="${REPO_DESC[$m]:-}"
    readme_repo_lines+="- **$m** -- ${desc:+$desc; }${repo_branch_line[$m]}"$'\n'
  done
  readme_repo_lines+=$'\n'
done

# ---- assemble the "## Branch tracking" body, since how a bare `git push`
# behaves here depends on whether PUSH_AS was set at creation.
if [[ -n "${PUSH_AS:-}" ]]; then
  tracking_lines=""
  for repo in "${requested[@]}"; do
    tracking_lines+="- **$repo**: \`${repo_branch_name[$repo]}\` -> \`origin/$PUSH_AS\`"$'\n'
  done
  branch_tracking_body="Every branch below was created with \`--no-track\`, then wired for \`PUSH_AS=$PUSH_AS\`:

- \`push.default upstream\` is set per worktree (\`git config --worktree\`) --
  scoped to that worktree only, so it doesn't change push behavior for the
  source repo's main checkout or any of its other worktrees.
- Each branch's \`branch.<name>.remote\`/\`.merge\` point at \`origin/$PUSH_AS\`
  in the *shared* repo config (branches aren't worktree-scoped -- this is
  the same config any real feature branch's tracking would live in).

So a bare \`git push\` from inside any repo below pushes straight to
\`origin/$PUSH_AS\`, no \`-u\` or explicit refspec needed:

$tracking_lines"
else
  branch_tracking_body="Every branch below was created with \`--no-track\`, so none of them
have an upstream configured. A bare \`git push\` from any repo here will be
rejected until you either:

- re-create this sandbox with \`PUSH_AS=<branch>\` to wire tracking
  automatically for every repo, or
- set it manually per repo you want to push from:
  \`git push -u origin <branch-name>\`"
fi

cat > "$sandbox_dir/README.md" <<EOF
# Sandbox $next${TITLE:+ ($TITLE)}

Created by \`create.sh\`. Each repo below is a \`git worktree\` of its source
repo (see repos.sh), not a clone -- untracked files from the source repo's
working tree never show up here.

Repos are grouped below by how they relate in a normal \`~/dev\` checkout
(shared stack, frontend/backend pair, etc). That relationship is about the
*source* checkouts only -- inside this sandbox every repo is worktreed to a
flat sibling directly under this directory, even ones (like ahmonolith)
that live nested inside another repo's tree (forerunner) normally.

## Repos

$readme_repo_lines
## Branch tracking

$branch_tracking_body

## Tear down

\`\`\`
make destroy N=$next
\`\`\`
EOF

echo
echo "Sandbox $next ready: $sandbox_dir"
echo "Repos: ${requested[*]}"
echo "Reference by index: make destroy N=$next"
