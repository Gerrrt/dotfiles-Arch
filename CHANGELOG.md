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

- **`bootstrap.sh --dry-run`** — previews the entire run (package plan + symlink
  plan + `/etc/wsl.conf` handling) and changes nothing. The shared library has
  supported `BLIB_DRY` end-to-end all along; this layer simply never exposed it.
- **Root `Makefile`** — `lint`, `bootstrap-dry`, `packages-check`, `secrets`,
  `core-lock`, `core-verify`. `lint` reproduces the CI gate exactly, so a failure
  is visible before pushing. This also makes `core.lock`'s own header instruction
  (“Regenerate … with: `make core-lock`”) true for the first time.
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

- **Privilege escalation goes through the library's `_blib_priv`**, honouring
  `BLIB_SU`, instead of a hardcoded `sudo`. This makes `bootstrap.sh` work as root
  and on `doas`-only boxes — and makes `provision()` runnable in a container, which
  Arch base images (no `sudo`) previously prevented.
- **Arch derivatives are accepted with a warning** rather than refused: the guard
  now falls back to `ID_LIKE=…arch…`, so EndeavourOS/Manjaro/CachyOS work.
- **`go install` for carapace/sesh logs its errors** to a file instead of
  `/dev/null`, and the module versions are overridable via `CARAPACE_VERSION` /
  `SESH_VERSION` (still defaulting to `latest` — see the note in `provision()`).
- **A failed run now says where it failed** (`ERR` trap), and a successful one
  prints the wiring tally and points at `core-doctor`.
- **`bootstrap.sh` installs the local `core/` pre-commit guard** on a fresh clone
  (`blib_install_core_guard`), catching a hand-edit at commit time rather than
  waiting for `core-integrity.yml` at PR time.
