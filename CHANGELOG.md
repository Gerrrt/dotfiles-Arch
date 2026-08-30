# Changelog

All notable changes to **dotfiles-Arch** are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

This repo carries **two version lines**, and they mean different things:

- **This repo's own `vX.Y.Z` tag**, cut automatically by `.github/workflows/auto-tag.yml`
  when a Core fan-out lands on `main`. That is what this file documents.
- **The vendored Core version**, recorded in [`core.lock`](core.lock) (`core_version` /
  `core_sha` / `core_tag`). Changes to Core are documented in `dotfiles-core`'s own
  CHANGELOG, not here — a `chore(core): core.lock → …` commit in this repo is a
  pointer, not an authored change.

Entries below therefore cover the **Arch OS-native layer only**: `bootstrap.sh`,
`install/packages.txt`, `os/`, `ssh/`, `wsl/`, and this repo's CI and meta files.

> **History note.** This file was introduced during a production-readiness audit,
> after `auto-tag.yml` had already cut the `v1.3.x` line. Tags prior to that point
> are not reconstructed here — `git log` remains the record for them.

## [Unreleased]

### Added

- **`make markdown`, wired into `make lint`.** `lint-call.yml`'s markdown leg has been
  **blocking** since dotgibson/dotfiles-core#592, but this repo had no local target for
  it — a required check nobody could run before pushing, and a `.markdownlint.jsonc` only
  CI ever read. `MD_FILES` uses the gate's own pathspec
  (`git ls-files '*.md' ':!:core/**'`), so the local run scans exactly what CI scans,
  recursively — a `'*.md'` glob would be top-level only and miss
  `pull_request_template.md`. All seven files already pass, so nothing rides along.
  It **skips** when `markdownlint-cli2` is absent rather than failing like the shellcheck
  arm: shellcheck is a pacman package, so missing means a box to fix, while
  markdownlint-cli2 is npm-only. Part of the fleet sweep in dotgibson/dotfiles-core#775.

- **`os/arch.capabilities`** — this repo's Core v5 capability declaration
  (dotgibson/dotfiles-core#663, #667). Core's `up`, maint runner and `core-doctor` now
  dispatch through it rather than through package-manager branches inside portable Core
  modules. `PKG_COUNT_PENDING` is `checkupdates` (from `pacman-contrib`, already in
  `install/packages.txt`), which syncs a copy of the database in user space and never
  touches the real sync DB. **`PKG_ASSUME_YES`, `PKG_UPGRADE_PARTIAL` and
  `MAINT_UNATTENDED_UPGRADE` are deliberately absent**: each omission is a safety
  statement Core honours exactly, so `up -i` refuses a partial upgrade and the scheduled
  runner refuses to upgrade this rolling distro unattended. Do not add them.
- **`make capabilities`** — validates `os/*.capabilities` against Core's schema via the
  vendored `core/scripts/check-capabilities.sh`, and runs as part of `make lint`.
- **`bootstrap.sh --dry-run`** — previews the entire run (package plan + symlink
  plan + `/etc/wsl.conf` handling) and changes nothing. The shared library has
  supported `BLIB_DRY` end-to-end all along; this layer simply never exposed it.
- **Root `Makefile`** — `lint`, `bootstrap-dry`, `packages-check`, `secrets`,
  `core-lock`, `core-verify`. `lint` reproduces the CI gate exactly, so a failure
  is visible before pushing.
- **`packages` workflow** — resolves every `install/packages.txt` name against the
  Arch repos on PR and weekly, without installing. Nothing previously checked the
  package list, on a rolling release where renames are routine.
- **Root `.gitattributes`, `.editorconfig`, `.shellcheckrc`** — Core ships all
  three, but EditorConfig/shellcheck/gitattributes resolution is directory-scoped,
  so they governed `core/**` only and this repo's own files had no policy.
- **`CODEOWNERS`, `pull_request_template.md`, `SECURITY.md`, and this file.**

### Fixed

- **`bootstrap.sh` could exit 0 having installed nothing.** `blib_read_pkgs`'
  exit status is lost inside the `< <(…)` process substitution, so a missing or
  empty `install/packages.txt` produced an empty array, a failed `pacman -S`, a
  zero-iteration fallback loop, and a success message. It now refuses to continue.
- **`bootstrap.sh` silently swallowed per-package install failures.** The fallback
  loop discarded every error, so a handful of renamed packages yielded a green run
  and a half-provisioned machine. Failures are now collected, reported at the end,
  and produce a non-zero exit — after wiring completes, so the box is still usable.
- **`bootstrap.sh` clobbered an existing `/etc/wsl.conf`.** Every other mutation in
  this system backs up first (`blib_link` → `.pre-dotfiles.<epoch>`); this one
  overwrote, losing any local `[automount]` / `[boot]` / `[network]` settings on a
  re-run of a script documented as idempotent. It now no-ops when already correct
  and backs up otherwise.
- **`pacorphans` passed all orphans to pacman as a single argument.** zsh does not
  word-split unquoted parameters, so `pacman -Rns $orphans` handed over one
  newline-joined string; now `${(f)orphans}`. `zsh -n` cannot catch this — the
  syntax is valid.
- **`--help` was coupled to the file's header line numbers** (`sed -n '2,17p' "$0"`),
  so editing the banner silently drifted the help text. Replaced with a `usage()`
  heredoc, matching the fix `core/scripts/sync-core.sh` already documents.
- **Stale `.gitignore` entry** `zsh/local.zsh` — a pre-v4 path that does not exist
  in this repo. Added credential, `.envrc`/`.direnv` and key-material patterns
  (`direnv` is installed by `packages.txt` and hooked into every shell).

### Changed

- **`make core-lock` no longer regenerates `core.lock`; it explains why and points at the
  fan-out.** (dotgibson/dotfiles-core#593) The target was added here to satisfy
  `core.lock`'s own header instruction, “Regenerate … with: `make core-lock`”. That
  instruction was the bug — Core removed it in dotfiles-core#454, because `core.lock` is
  written by `sync-core.sh` in the same commit as the subtree pull and was never meant to
  have a second writer.

  Keeping the generator meant this repo owned a second definition of a format Core owns,
  and it had already drifted from it in three ways: it hardcoded `core_branch=main`, so
  regenerating a lock that had been pinned to a released commit silently replaced that
  provenance with a branch name; it re-emitted the removed header line, reintroducing the
  very instruction it existed to satisfy; and it predates dotfiles-core#453, which renamed
  the field to `core_ref` — so running it now would emit a lock the rest of the fleet
  disagrees with.

  `core-verify` is unchanged and remains the way to check this repo's vendored `core/`.

- **Privilege escalation goes through the library's `_blib_priv`**, honouring
  `BLIB_SU`, instead of a hardcoded `sudo`. This makes `bootstrap.sh` work as root
  and on `doas`-only boxes — and makes `provision()` runnable in a container, which
  Arch base images (no `sudo`) previously prevented.
- **Arch derivatives are accepted with a warning** rather than refused: the guard
  now falls back to `ID_LIKE=…arch…`, so EndeavourOS/Manjaro/CachyOS work.
- **`go install` for sesh logs its errors** to a file instead of `/dev/null`, and
  the module version is overridable via `SESH_VERSION` (still defaulting to
  `latest` — see the note in `provision()`). carapace is a printed `paru` hint and
  takes no version override, per the analysis in
  [#89](https://github.com/dotgibson/dotfiles-Arch/pull/89): `go install` cannot
  work for any version of it. That error logging is what makes such a failure
  visible in the first place — the old `/dev/null` form is precisely why the
  carapace call could fail on every bootstrap without anyone noticing.
- **A failed run now says where it failed** (`ERR` trap), and a successful one
  prints the wiring tally and points at `core-doctor`.
- **`bootstrap.sh` installs the local `core/` pre-commit guard** on a fresh clone
  (`blib_install_core_guard`), catching a hand-edit at commit time rather than
  waiting for `core-integrity.yml` at PR time.
