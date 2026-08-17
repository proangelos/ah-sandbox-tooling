# Source-of-truth repo map for the sandbox create/destroy scripts.
# Edit this file to add, remove, or move repos -- create.sh and destroy.sh both read it.
# Sourced, not executed: no shebang, no `set -e` (would leak into the caller).

declare -A REPOS=(
  [forerunner]="$HOME/dev/forerunner"
  [ahmonolith]="$HOME/dev/forerunner/repos/ahmonolith"
  [ahportal-ui]="$HOME/dev/forerunner/repos/ahportal-ui"
  [v7-react]="$HOME/dev/forerunner/repos/v7-react"
  [cms-api]="$HOME/dev/cms-api"
  [cms-ui]="$HOME/dev/cms-ui"
  [tango-service]="$HOME/dev/tango-service"
  [p2p-service]="$HOME/dev/p2p-service"
)

# Always included in every new sandbox.
BASE_REPOS=(forerunner ahmonolith ahportal-ui v7-react)

# Available via WITH="repo1 repo2 ..."; not included unless requested.
OPTIONAL_REPOS=(cms-api cms-ui tango-service p2p-service)

# Branch each repo's sandbox worktree branches off of, after fetching it fresh
# from origin. Applies to every repo above unless overridden below.
DEFAULT_BRANCH="feat/site-builder/main"

# Tried if DEFAULT_BRANCH (or a repo's BRANCH_OVERRIDES entry) doesn't exist
# on that repo's origin -- e.g. repos that never had a feat/site-builder/main
# cut still get a usable base instead of create.sh erroring out on them.
FALLBACK_BRANCH="feat/port/main"

# Per-repo exceptions to DEFAULT_BRANCH, e.g.:
#   [v7-react]="feat/site-builder/main"
declare -A BRANCH_OVERRIDES=(
)

# Wherever create.sh/destroy.sh actually live -- SCRIPT_DIR is set by whichever
# of them sourced this file, so sandboxes are created next to this repo no
# matter where it's checked out.
SANDBOX_ROOT="$SCRIPT_DIR"
