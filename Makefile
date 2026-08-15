# Makefile — a discoverable façade over this repo's entry points.
# ──────────────────────────────────────────────────────────────────────────────
# Mirrors dotfiles-core/Makefile in spirit: it adds NO logic of its own beyond
# reproducing, verbatim, what CI already runs — so `make lint` == the `lint /
# shell lint` job, and a contributor stops finding out about a failure only after
# pushing. Before this file existed the repo had no local commands at all, which
# also made core.lock's own header ("Regenerate … with: make core-lock") false.
#
# Core's own gate (`make audit`, `make sync`) lives UPSTREAM in dotfiles-core and
# is deliberately not duplicated here — core/ is vendored and read-only in this
# repo. See CLAUDE.md.
#
# NOTE: run these from inside the Linux filesystem, not from Windows over
# \\wsl.localhost — a Windows-side git reads the share as mode 0644 and would
# strip the exec bit off every script. See .gitattributes.
# ──────────────────────────────────────────────────────────────────────────────
.DEFAULT_GOAL := help
.PHONY: help lint bootstrap-dry packages-check secrets core-lock core-verify

# bash explicitly, not make's default /bin/sh: packages-check SOURCES
# core/lib/bootstrap-lib.sh, which is bash (arrays, [[ ]]). Arch happens to point
# /bin/sh at bash, so this would appear to work here and break on any host that
# doesn't — the kind of latent portability bug this repo exists to avoid.
SHELL := /bin/bash

# Path to a dotfiles-core checkout — the reference for the two provenance targets.
# Defaults to a sibling clone, which is the layout sync-core.sh assumes.
CORE_REPO ?= $(CURDIR)/../dotfiles-core

# The same exclusions and suppressions lint-call.yml uses. core/** is excluded
# because it is gated upstream by dotfiles-core's own CI.
SH_FILES   = $(shell git ls-files '*.sh' ':!:core/**')
ZSH_FILES  = $(shell git ls-files '*.zsh' ':!:core/**')
export SHELLCHECK_OPTS = -e SC1090 -e SC1091 -e SC2015 -e SC2088

help: ## Show this help
	@echo "dotfiles-Arch — make targets:"
	@grep -E '^[a-z][a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) \
		| sed -E 's/:.*## /\t/' | sort | awk -F'\t' '{printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "  Core's audit/sync live upstream in dotfiles-core (core/ is vendored, read-only here)."

lint: ## shellcheck + bash -n on repo-owned *.sh, zsh -n on repo-owned *.zsh (== the CI gate)
	@rc=0; \
	if [ -z "$(SH_FILES)" ]; then echo "no repo-owned .sh"; else \
	  if command -v shellcheck >/dev/null 2>&1; then \
	    echo "shellcheck $(SH_FILES)"; shellcheck -x $(SH_FILES) || rc=1; \
	  else echo "!! shellcheck not installed — install it, or CI is your only gate"; rc=1; fi; \
	  for f in $(SH_FILES); do echo "bash -n $$f"; bash -n "$$f" || rc=1; done; \
	fi; \
	if [ -z "$(ZSH_FILES)" ]; then echo "no repo-owned .zsh"; else \
	  if command -v zsh >/dev/null 2>&1; then \
	    for f in $(ZSH_FILES); do echo "zsh -n $$f"; zsh -n "$$f" || rc=1; done; \
	  else echo "!! zsh not installed — cannot syntax-check $(ZSH_FILES)"; rc=1; fi; \
	fi; \
	[ $$rc -eq 0 ] && echo "lint OK" || echo "lint FAILED"; exit $$rc

bootstrap-dry: ## Preview a full bootstrap (symlink plan + package plan), changing nothing
	@./bootstrap.sh --dry-run

packages-check: ## Resolve every install/packages.txt name against the repos WITHOUT installing
	@command -v pacman >/dev/null 2>&1 || { echo "pacman not found — run this on Arch"; exit 1; }
	@set -e; \
	. core/lib/bootstrap-lib.sh; \
	pkgs=$$(blib_read_pkgs install/packages.txt); \
	[ -n "$$pkgs" ] || { echo "no packages parsed from install/packages.txt"; exit 1; }; \
	echo ":: resolving $$(echo "$$pkgs" | wc -l) package names (no download, no install)"; \
	rc=0; \
	for p in $$pkgs; do \
	  pacman -Si "$$p" >/dev/null 2>&1 || { echo "  UNRESOLVED: $$p"; rc=1; }; \
	done; \
	if [ $$rc -eq 0 ]; then echo "all package names resolve"; else \
	  echo "^^ renamed or dropped upstream (Arch is a ROLLING release) — check archlinux.org/packages"; fi; \
	exit $$rc

secrets: ## Scan the full git HISTORY for credentials (gitleaks — not just the working tree)
	@command -v gitleaks >/dev/null 2>&1 || { \
	  echo "gitleaks not installed. Core pins 8.30.1 in core/scripts/tool-versions.env:"; \
	  echo "  go install github.com/gitleaks/gitleaks/v8@latest   # or: pacman -S gitleaks"; exit 1; }
	@gitleaks detect --source . --redact --verbose

core-lock: ## Regenerate core.lock after a manual `git subtree pull` (needs CORE_REPO)
	@set -e; \
	[ -d "$(CORE_REPO)/.git" ] || { \
	  echo "CORE_REPO=$(CORE_REPO) is not a dotfiles-core checkout."; \
	  echo "core.lock records the FULL Core commit SHA, but the git-subtree squash commit"; \
	  echo "in this repo records only the SHORT form — expanding it needs Core's object DB."; \
	  echo "Clone dotfiles-core as a sibling, or: make core-lock CORE_REPO=/path/to/dotfiles-core"; \
	  exit 1; }; \
	short=$$(git log -1 --format=%s --grep="^Squashed 'core/' changes from" \
	         | sed -n "s/.*\.\.\([0-9a-f]\{7,\}\).*/\1/p"); \
	[ -n "$$short" ] || { echo "no \"Squashed 'core/' changes\" commit found — was core/ vendored via git subtree?"; exit 1; }; \
	full=$$(git -C "$(CORE_REPO)" rev-parse "$$short^{commit}" 2>/dev/null) || { \
	  echo "$$short is not an object in $(CORE_REPO) — fetch it there first"; exit 1; }; \
	version=$$(tr -d '[:space:]' < core/core.version); \
	tag=$$(git -C "$(CORE_REPO)" describe --tags "$$full" 2>/dev/null || echo ''); \
	{ echo "# GENERATED by dotfiles-core sync-core.sh — vendored Core provenance (B1)."; \
	  echo "# Regenerate after a manual 'git subtree pull' with: make core-lock"; \
	  echo "core_version=$$version"; \
	  echo "core_sha=$$full"; \
	  echo "core_branch=main"; \
	  [ -n "$$tag" ] && echo "core_tag=$$tag"; \
	  true; } > core.lock; \
	echo "core.lock → $$full (v$$version$${tag:+, $$tag})"

core-verify: ## Verify the vendored core/ is pristine vs core.lock (needs CORE_REPO)
	@[ -x "$(CORE_REPO)/scripts/core-integrity.sh" ] || { \
	  echo "need a dotfiles-core checkout at CORE_REPO=$(CORE_REPO)"; exit 1; }
	@"$(CORE_REPO)/scripts/core-integrity.sh" --self "$(CURDIR)"
