SANDBOX_ROOT := $(HOME)/dev/sandbox

.PHONY: help new list destroy
.DEFAULT_GOAL := help

help: ## Show this help
	@echo "Usage: make <target> [ARGS...]"
	@echo
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*## "}; {printf "  %-10s %s\n", $$1, $$2}'

# make new                                             base repos only
# make new WITH="cms-api tango-service"                 base + optional repos
# make new WITH="cms-api" PUSH_AS=fix-auth-bug          + wires remote tracking to origin/fix-auth-bug
new: ## Create a new numbered sandbox (WITH="repo1 repo2", PUSH_AS=branch-name)
	@WITH="$(WITH)" PUSH_AS="$(PUSH_AS)" $(SANDBOX_ROOT)/create.sh

list: ## List existing sandbox numbers
	@ls -1 $(SANDBOX_ROOT) 2>/dev/null | grep -E '^[0-9]+$$' || echo "no sandboxes yet"

# make destroy N=3
destroy: ## Tear down a sandbox and its worktrees/branches (make destroy N=<n>)
	@test -n "$(N)" || { echo "usage: make destroy N=<sandbox number>" >&2; exit 1; }
	@$(SANDBOX_ROOT)/destroy.sh "$(N)"
