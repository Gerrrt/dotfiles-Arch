#!/usr/bin/env bash
# test/check-packages.sh
# ──────────────────────────────────────────────────────────────────────────────
# Does every package name in install/packages.txt still exist in the Arch repos —
# and is the manifest itself well-formed?
#
# WHY THIS FILE EXISTS AT ALL. `bootstrap.sh`'s provision() installs the list in one
# `pacman -Syu --needed` and, when that fails, retries package-by-package and records
# each casualty in PROVISION_FAILED. That resilience is right on a live box — one dead
# name should not sink the whole install — but it means a rename, a drop or a typo is
# only discovered by someone running a real bootstrap on real hardware. CI never gets
# there: bootstrap.yml runs the reusable test with `--links-only`, which skips
# provision() entirely (see CLAUDE.md). This turns that blind spot into a gate. It
# installs NOTHING.
#
# It is also the repo's `test/` floor (dotgibson/dotfiles-core#691), modelled on
# dotfiles-Debian/test/check-packages.sh — with one check deliberately dropped and one
# added:
#
#   • NO VERSION FLOORS. Debian's script compares each candidate against a `# min:X.Y.Z`
#     annotation, because on a frozen archive `neovim` resolves happily at 0.9.5 and a
#     resolution-only gate would call that box healthy. Arch is a ROLLING release: the
#     repos carry the current upstream release by construction, so a floor would encode
#     a question the archive cannot answer wrongly. install/packages.txt declares no
#     floors, and this does not invent a syntax for them. The drift risk here is the
#     opposite one — names MOVING (doggo went AUR→extra in 2025) or disappearing.
#
#   • DUPLICATE DETECTION, which runs everywhere. Resolution needs pacman, so it can
#     only run on Arch; a hand-maintained 60-line manifest grouped into eight commented
#     sections is exactly where the same name gets pasted into two sections. Checking
#     that needs no package manager, so `make test` is not a no-op off-Arch.
#
# WHAT IT DOES NOT CHECK: the AUR. `pacman -Si` sees the official repos only, which is
# the right scope — install/packages.txt is the pacman list, and the four AUR-only tools
# (carapace, sesh, op, viddy) are printed hints in bootstrap.sh, not entries here. So an
# unresolved name below means "gone from core/extra", which may mean it moved TO the AUR;
# the failure text says so.
#
# Exit codes:
#   0  the manifest is well-formed and every name resolved (or a clean skip: no pacman)
#   1  usage/environment failure — a missing or unreadable manifest, a broken checkout
#   2  one or more names failed the checks — the drift signal
#
# Usage:
#   test/check-packages.sh                      # install/packages.txt
#   test/check-packages.sh install/packages.txt
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
# `set -e` is deliberately OFF here — the exit code IS the result, and the checks below
# are meant to run to completion and report everything at once rather than stopping at
# the first bad name. So guard the cd explicitly: continuing in the wrong directory would
# read the wrong manifest and pass.
cd -- "$REPO_ROOT" || exit 1

if [[ -r core/lib/ux.sh ]]; then
  # shellcheck source=core/lib/ux.sh
  source core/lib/ux.sh
fi
say() { printf '%s::%s %s\n' "${UX_BLU:-}" "${UX_RST:-}" "$*"; }
ok() { printf '%s%s%s %s\n' "${UX_GRN:-}" "${UX_OK:-+}" "${UX_RST:-}" "$*"; }
bad() { printf '%s%s%s %s\n' "${UX_YEL:-}" "${UX_WARN:-!}" "${UX_RST:-}" "$*" >&2; }

manifest="${1:-install/packages.txt}"
[[ -f "$manifest" ]] || {
  bad "manifest not found: $manifest"
  exit 1
}

# Reuse Core's parser rather than re-implementing the comment/whitespace rules: it is the
# SAME function bootstrap.sh feeds pacman, so this checks exactly the names that would
# really be installed — inline-comment stripping included, which matters in a file where
# most lines carry one.
if [[ -r core/lib/bootstrap-lib.sh ]]; then
  # shellcheck source=core/lib/bootstrap-lib.sh
  source core/lib/bootstrap-lib.sh
else
  bad "core/lib/bootstrap-lib.sh not found — is the core/ subtree vendored?"
  exit 1
fi

# blib_read_pkgs_into, not `mapfile < <(blib_read_pkgs …)`: mapfile reports its OWN
# status, so a missing manifest would hand us an empty array with a success status. The
# _into form propagates the read failure (core/lib/bootstrap-lib.sh:391).
# Declared here only so shellcheck can see it assigned (SC2154): blib_read_pkgs_into
# fills it through an `eval`, which static analysis cannot follow. It empties the array
# itself before reading, so this is not a second initialisation with a meaning.
pkgs=()
blib_read_pkgs_into pkgs "$manifest" || exit 1
((${#pkgs[@]})) || {
  bad "$manifest parsed to zero package names"
  exit 1
}
say "$manifest — ${#pkgs[@]} names"

rc=0

# ── 1. manifest hygiene: no name listed twice ─────────────────────────────────
# No pacman needed, so this is the part that runs on any host.
mapfile -t dupes < <(printf '%s\n' "${pkgs[@]}" | sort | uniq -d)
if ((${#dupes[@]})); then
  bad "${#dupes[@]} package name(s) appear more than once:"
  printf '    %s\n' "${dupes[@]}" >&2
  bad "pacman tolerates the repeat; the manifest should not — delete one, and check you"
  bad "did not mean to add a DIFFERENT package to the second section."
  rc=2
fi

# ── 2. resolution against the official repos ──────────────────────────────────
if ! command -v pacman >/dev/null 2>&1; then
  say "no pacman on this host — skipping the resolution check (the packages workflow"
  say "runs it in an archlinux:latest container, which is where the answer is true)."
  exit "$rc"
fi

# `pacman -Si` reads the SYNC DB: no download, no install. It needs that DB to exist,
# though — a bare container has none, and an empty DB would report every name as
# missing, which is a false red rather than a finding. Refuse instead of guessing, and
# never `-Sy` from here: a bare sync against a stale image is the partial upgrade this
# repo's golden rule forbids (CLAUDE.md), and a test script is the last place that
# should mutate a box's package state.
if [[ -z "$(ls -A /var/lib/pacman/sync 2>/dev/null)" ]]; then
  bad "the pacman sync DB is empty — run 'pacman -Syu' first (NEVER a bare -Sy)."
  exit 1
fi

say "resolving ${#pkgs[@]} package names (no download, no install)"
missing=()
for p in "${pkgs[@]}"; do
  pacman -Si "$p" >/dev/null 2>&1 || missing+=("$p")
done

echo
if ((${#missing[@]})); then
  bad "${#missing[@]} of ${#pkgs[@]} name(s) are NOT in the official repos:"
  printf '    %s\n' "${missing[@]}" >&2
  rc=2
else
  ok "all ${#pkgs[@]} names resolve against core/extra."
fi

if ((rc == 0)); then
  exit 0
fi

cat >&2 <<'EOF'

An unresolved name on a ROLLING release is one of:
  • a rename    — find the new name (pacman -Ss <fragment>) and update install/packages.txt
  • a move      — it went to the AUR; drop it here and print a `paru -S` hint in
                  bootstrap.sh instead, the way carapace/sesh/op/viddy already are
  • a drop      — gone upstream; remove it, or install it out-of-band in bootstrap.sh
  • a typo      — fix it
Cross-check at https://archlinux.org/packages/
EOF
exit "$rc"
