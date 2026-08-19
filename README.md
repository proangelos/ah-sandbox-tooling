# Repo layout

Notes for whoever (human or Claude) touches this tool's config next. The
repos this tool sandboxes are **not** all laid out the same way under
`~/dev/`, and that split is deliberate, not a bug -- `REPOS` is a plain
name -> path lookup specifically so it can absorb this.

## Customizing for your setup

Repo paths, branches, and grouping live in `.env.default` (tracked --
shared defaults for the team) and are loaded by `repos.sh`. If your repos
live somewhere other than the paths in `.env.default` -- a different root,
a different sync layout, or you just don't have `forerunner` managing
things the same way -- don't edit `.env.default` directly. Instead, copy
`.env.example` to `.env` (gitignored) and override just what differs for
you:

```sh
cp .env.example .env
```

`.env` is sourced after `.env.default`, so it only needs to state deltas:

```sh
# Override an existing repo's path
REPOS[forerunner]="$HOME/code/forerunner"

# Add a repo .env.default doesn't know about (SOURCE_BRANCHES is required)
REPOS[my-service]="$HOME/dev/my-service"
SOURCE_BRANCHES[my-service]="main"
OPTIONAL_REPOS+=(my-service)
```

Both files are plain bash (associative arrays), not real dotenv `KEY=VALUE`
syntax -- repo entries need multiple fields (path, branch, group,
description), which a flat format can't hold cleanly. See `.env.example`
for the full syntax reference.

## Two different layouts

**`forerunner`** (`~/dev/forerunner`) is the local-dev orchestrator: docker
compose + `configs/stacks/*.yaml` "stack" definitions + its own repo-sync
tool (`make repos`, backed by `forerunner repos sync --stack <name>`). That
sync tool clones a specific set of app repos *into* `~/dev/forerunner/repos/`
for it to manage. Three of them are repos this sandbox tool cares about:

- **`ahmonolith`** -- `~/dev/forerunner/repos/ahmonolith` -- the core monolith backend
- **`ahportal-ui`** -- `~/dev/forerunner/repos/ahportal-ui` -- portal frontend for legacy client
- **`v7-react`** -- `~/dev/forerunner/repos/v7-react` -- portal frontend for v8/blueprint clients

All three are part of forerunner's `monolith` stack and are nested *under*
`forerunner`'s own directory because forerunner's tooling put them there, not
because of anything this sandbox tool does.

**`cms-api`** and **`cms-ui`** (`~/dev/cms-api`, `~/dev/cms-ui`) are a separate
service pair, checked out as plain top-level siblings of `forerunner` under
`~/dev/` -- *not* nested inside it. Forerunner's `blueprint` stack does
reference them by name for its own docker-compose purposes, but that's only
orchestration config; it has nothing to do with where their git checkouts
physically live. Same story for `tango-service` and `p2p-service`
(forerunner's `all-services` stack), also plain `~/dev/<repo>` siblings.

## Why this matters here

`.env.default` hardcodes each repo's source path individually instead of
deriving them from one shared parent, precisely because of the split above.
If forerunner's sync tooling ever starts/stops managing a given repo, or a
repo moves, `.env.default`'s `REPOS` map needs a matching one-line edit --
there is no clever path convention to lean on instead. If it's just *your*
layout that differs from the team default, override it in `.env` instead
(see "Customizing for your setup" above) rather than editing the tracked
file.

`.env.default` is the source of truth for the actual paths, base/optional
grouping, and default branches. This file is just the "why" behind its
shape.

## How sandbox worktrees & branches work

Each repo in a sandbox is a `git worktree` of the matching source repo, not a
clone -- it shares that repo's `.git` object store and history, and shows up
in `git -C <source> worktree list`. This is also why a source repo's own
untracked files (e.g. an app's own `.env`, unrelated to this tool's
`.env`/`.env.default`) never appear in a sandbox: a worktree only populates
tracked files, regardless of what's sitting in the source repo's own
working tree.

**Base branch.** Before creating the worktree, `create.sh` runs
`git fetch origin <branch>` in the source repo (`<branch>` = that repo's
entry in `SOURCE_BRANCHES` -- see `.env.default`), then branches the worktree off
`origin/<branch>`. Sandboxes always start from a fresh remote-fetched state
this way, independent of whatever branch/commit the source repo's own
checkout happens to be sitting on. Every repo in `REPOS` needs its own
`SOURCE_BRANCHES` entry -- there's no default/fallback guessing, since repos
here have already diverged (some never had a `feat/site-builder/main` cut,
`p2p-service` uses its own `feat/p2p/main` convention, etc). `create.sh`
errors out immediately if a repo is missing one.

**Local branch name.** Always `sandbox/<n>/<repo>`, keyed off the sandbox's
numeric index only -- never its optional `-<title>` suffix. This is what lets
a titled sandbox dir (`3-docsTile/`) still resolve cleanly by index alone.

**No default tracking.** The worktree is created with `--no-track`. Without
it, git's `branch.autoSetupMerge` default would silently set the new branch
to track `origin/<branch>` (e.g. `master`) just for having been branched from
it -- a live wire, since pushing to `@{upstream}` later would go straight to
master. With no tracking configured, a bare `git push` simply has nowhere to
go until you tell it where.

**`PUSH_AS=<name>` (optional).** Wires that one worktree's branch to track
`origin/<name>` instead, so a bare `git push` goes straight there:

- `branch.sandbox/<n>/<repo>.remote` / `.merge` are set to point at
  `origin/<name>`. These live in the source repo's shared config (branches
  are a shared, exclusively-checked-out resource, same as any real feature
  branch), not anything worktree-specific.
- `push.default upstream` is set too, but scoped to *this worktree only* via
  `git config --worktree` (after enabling `extensions.worktreeConfig` once
  per source repo). This is what allows a push to a differently-named
  upstream without requiring `-u`/an explicit refspec, and critically,
  without changing push behavior for the source repo's main checkout or any
  of its other worktrees.

Without `PUSH_AS`, none of the above is touched -- push manually with an
explicit refspec (`git push origin HEAD:<remote-branch>`).

**Teardown.** `destroy.sh` runs `git worktree remove --force` and
`git branch -D` for each repo *from the source repo*, not the sandbox dir.
Deleting the branch automatically strips its `branch.<name>.*` config, so any
`PUSH_AS` wiring cleans itself up with it -- no separate cleanup step needed.
