# Loads repo config for the sandbox create/destroy scripts.
# Sourced, not executed: no shebang, no `set -e` (would leak into the caller).
#
# The actual repo data (REPOS, BASE_REPOS, OPTIONAL_REPOS, SOURCE_BRANCHES,
# REPO_GROUP, REPO_DESC) lives in .env.default (tracked shared defaults),
# with .env (gitignored, optional) layered on top for per-developer path
# overrides or additional repos -- see .env.example for the override syntax.
source "$SCRIPT_DIR/.env.default"
[[ -f "$SCRIPT_DIR/.env" ]] && source "$SCRIPT_DIR/.env"

# Wherever create.sh/destroy.sh actually live -- SCRIPT_DIR is set by whichever
# of them sourced this file, so sandboxes are created next to this repo no
# matter where it's checked out.
SANDBOX_ROOT="$SCRIPT_DIR"
