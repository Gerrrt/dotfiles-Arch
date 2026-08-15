# Security Policy

## What this repo is

`dotfiles-Arch` ships **configuration only** — a `pacman` package list, shell/tmux/git
overlays for Arch, an SSH *client* config, and a `bootstrap.sh` that symlinks them into
place. It is not a running service, exposes no network surface, and stores no
credentials or machine state.

The shared Core layer is vendored read-only under `core/`; report issues in that code
against [`dotfiles-core`](https://github.com/dotgibson/dotfiles-core) instead, since a
fix there fans out to every OS repo.

## Reporting a vulnerability

Use **[private vulnerability reporting](https://github.com/dotgibson/dotfiles-Arch/security/advisories/new)**
rather than a public issue. Please don't open a public issue for anything that would
expose a credential or a working attack against a user's machine.

If private reporting is unavailable, email the address in the README's Contact section.

## What is in scope

Because this repo runs `bootstrap.sh` with elevated privileges on a fresh machine, the
things actually worth reporting are:

- **Privilege escalation in `bootstrap.sh`** — anything that lets an unprivileged input
  (a package name, a username, a file in the repo) influence what runs under
  `_blib_priv` / `sudo`.
- **Destructive behaviour** — a path where bootstrap overwrites or deletes user data
  without the documented `.pre-dotfiles.<epoch>` backup.
- **Weakened SSH posture** in [`ssh/config`](ssh/config) — a downgraded algorithm list,
  or a `StrictHostKeyChecking`/`UserKnownHostsFile` relaxation escaping the commented
  throwaway-lab template into an active block.
- **Supply chain** — the unpinned `go install` of `carapace`/`sesh` in `provision()`
  (best-effort, `$HOME`-scoped, and overridable via `CARAPACE_VERSION`/`SESH_VERSION`;
  the AUR route is the version-controlled alternative), or a workflow pinned somewhere
  it should not be.
- **Committed secrets** — see below.

## Secret handling

No secrets are committed, and the layout is designed so they cannot be:

- **SSH keys are never tracked.** `.gitignore` allowlists exactly one file
  (`ssh/*` ignored, `!ssh/config`). `bootstrap.sh` creates `~/.ssh` and
  `~/.ssh/sockets` as `0700` and the config as `0600`.
- **Git identity is never tracked.** `core/git/local.gitconfig.example` is *copied*
  once to `~/.config/git/local.gitconfig` (never symlinked, never relinked), so your
  name/email/signing key stay off the repo.
- **Host-local shell overrides live outside the repo** at `$ZDOTDIR/99-local.zsh`.
- **Credentials are kept out of history** by Core: `zsh/15-history.zsh` sets
  `HISTORY_IGNORE` for `op`/`pass`/`--token`/`--password`-style commands, and
  `atuin/config.toml` carries matching `secrets_filter` / `history_filter`.
- **`.envrc` and `.direnv/` are ignored.** `direnv` is installed by
  `install/packages.txt` and hooked into every interactive shell by `os/arch.zsh`, so
  an `.envrc` here would be *loaded*.

Run `make secrets` (gitleaks) before pushing. GitHub secret scanning with **push
protection** is the backstop — it rejects a credential at `git push`, before it is
ever published.

## Supported versions

Only `main` and the latest tag are supported. This repo's tags track Core fan-outs
(see [`CHANGELOG.md`](CHANGELOG.md)); there are no maintained release branches.
