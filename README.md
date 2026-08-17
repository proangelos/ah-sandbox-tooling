# Repo layout

Notes for whoever (human or Claude) touches `repos.sh` next. The repos this
tool sandboxes are **not** all laid out the same way under `~/dev/`, and
that split is deliberate, not a bug -- `repos.sh`'s `REPOS` map is a plain
name -> path lookup specifically so it can absorb this.

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

`repos.sh` hardcodes each repo's source path individually instead of
deriving them from one shared parent, precisely because of the split above.
If forerunner's sync tooling ever starts/stops managing a given repo, or a
repo moves, `repos.sh`'s `REPOS` map needs a matching one-line edit -- there
is no clever path convention to lean on instead.

`repos.sh` is the source of truth for the actual paths, base/optional
grouping, and default branches. This file is just the "why" behind its
shape.
