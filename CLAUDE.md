# CLAUDE.md — dotfiles-Arch

Project memory for Claude Code, auto-loaded every session. For the shared Core
rules (the load order, the "is it Core?" test, the manifest contract) see
`core/README.md` and `core/CONTRIBUTING.md`.

## What this repo is

`dotfiles-Arch` is the **OS-native layer for Arch Linux** in a **eleven-repo dotfiles system** built on a three-layer
model (Core → OS-native → Role). Arch is stamped from the Fedora template (see `core/PORTING-MATRIX.md`). Rolling release — never `pacman -Sy <pkg>` without `-u`; partial upgrades break things. Most tools are in the official repos, the rest one `paru -S` away in the AUR.

## The rule that bites

`core/` is a **vendored `git subtree` copy of [dotfiles-core](https://github.com/dotgibson/dotfiles-core)** — it
is *not* editable here. Anything you change under `core/` is overwritten on the
next sync. To change shared Core config, edit it **in dotfiles-core**, run
`make audit` there, then `make sync` to fan it out to every OS repo.

What belongs **here** is only the OS-native layer: the `pacman`/AUR package list, clipboard + paths, and the bootstrap.

## The other rule that bites: work from Linux, not from Windows

This repo lives on ext4 and is also reachable from Windows at
`\\wsl.localhost\archlinux\home\<you>\code\dotgibson\dotfiles-Arch`. **Do git and
file writes from inside WSL.** Over that UNC share:

- a Windows-side git reports every file as mode `0644`, so `git diff` shows ~35
  phantom `100755 => 100644` changes. Committing them strips `+x` from
  `bootstrap.sh` and every script under `core/` — which Core's audit asserts, and
  which changes `HEAD:core`'s tree object, so `core-integrity.yml` would then red
  every PR.
- files created from Windows land **owned by `root:root`**, so you cannot even
  `chmod` them back as your normal user.
- Windows git defaults to `core.autocrlf=true`. `core/.gitattributes` protects
  `core/**`; the root `.gitattributes` now protects everything else.

Related: running Core's `scripts/audit-core.sh` from the Windows side **silently
skips** its manifest-drift and exec-bit sections — both gate on `git rev-parse`,
which fails with a dubious-ownership error, and the audit treats a missing
prerequisite as SKIP rather than FAIL. That is a green-because-absent result, not
a pass.

## Local commands

`make` (see the root `Makefile`) — `lint` reproduces the CI gate exactly,
`bootstrap-dry` previews a full install, `packages-check` resolves every package
name without installing, `secrets` runs gitleaks, and `core-lock` / `core-verify`
handle vendored-Core provenance (both need a `dotfiles-core` checkout at
`CORE_REPO`). Core's own `make audit` / `make sync` live **upstream**, not here.

Note CI never exercises `provision()` — the reusable bootstrap test only runs
`--links-only`. Package installation is covered by `make packages-check` and the
`packages` workflow; anything else in `provision()` needs a real box or container.

## Where things are

- `os/arch.zsh` — clipboard + package-manager aliases for Arch
- `os/arch.conf`, `os/arch.gitconfig` — tmux + git OS overlays
- `install/packages.txt` — Arch package names
- `bootstrap.sh` — symlinks Core + OS files into place
- `Makefile` — the local entry points (lint, dry-run, package + secret checks)
- `SETUP.md` — the Arch install walkthrough
- `core/` — vendored Core (read-only here; edit upstream in dotfiles-core)
