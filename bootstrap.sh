#!/usr/bin/env bash
# dotfiles-Arch/bootstrap.sh
# ──────────────────────────────────────────────────────────────────────────────
# Provision an Arch Linux box (desktop or WSL/ArchWSL) and wire up dotfiles.
# Idempotent — safe to re-run. This is the OS-NATIVE layer; Core (zsh/tmux/nvim/
# git) is vendored under core/ and symlinked in via core/lib/bootstrap-lib.sh.
#
# Run `./bootstrap.sh --help` for usage — see usage() below, which is the single
# definition (deliberately NOT `sed -n '2,17p' "$0"`: that form couples --help to
# this banner's line numbers, so editing the header silently drifts the help text.
# core/scripts/sync-core.sh records the same fix for the same reason.)
# ──────────────────────────────────────────────────────────────────────────────
# `-E` (errtrace) so the ERR trap below fires inside functions too, not just at
# the top level — without it a failure inside provision() aborts with no context.
set -eEuo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
LINKS_ONLY=0
DO_FLATPAK=1
# Packages that could not be installed, collected by provision() so the run can
# finish wiring the box and THEN report honestly + exit non-zero. Half-provisioning
# silently (the old behaviour) is the worse failure: you get a green run and a
# machine missing tools you only discover days later.
PROVISION_FAILED=()

usage() {
  cat <<'EOF'
bootstrap.sh — provision an Arch box (desktop or WSL/ArchWSL) and wire up dotfiles.

  ./bootstrap.sh                 full: pacman packages + extras + symlinks
  ./bootstrap.sh --links-only    just (re)create symlinks (no pacman)
  ./bootstrap.sh --dry-run       preview EVERYTHING, change nothing
  ./bootstrap.sh --no-flatpak    skip Flathub/GUI apps (recommended on WSL)
  ./bootstrap.sh --only zsh,nvim link ONLY these Core module groups
  ./bootstrap.sh --skip tmux     link everything EXCEPT these groups
  ./bootstrap.sh -h, --help      show this help and exit

Module groups (for --only/--skip): zsh nvim tmux git prompt tools
  They affect the WIRING steps only, never package provisioning. Combine with
  --links-only to re-wire a subset of configs without touching pacman. If both
  --only and --skip are given, --only wins (it is an allowlist).

Env overrides:
  BLIB_SU     privilege escalator (default: sudo; set empty when already root,
              or `doas` on a box without sudo)
  BLIB_DRY    set to 1 for the same effect as --dry-run
  CARAPACE_VERSION / SESH_VERSION
              Go module versions for the two tools not in Arch's repos
              (default: latest — see the note in provision())
EOF
}

# --only/--skip are validated by the shared lib (blib_select), sourced AFTER this
# loop — capture the raw values now and apply them below.
ONLY_RAW=""; SKIP_RAW=""; ONLY_SEEN=0; SKIP_SEEN=0

while [[ $# -gt 0 ]]; do case "$1" in
  --links-only) LINKS_ONLY=1 ;;
  --dry-run | -n) BLIB_DRY=1 ;;
  --no-flatpak) DO_FLATPAK=0 ;;
  --only) [[ $# -ge 2 ]] || { echo "--only requires module names, e.g. --only zsh,nvim" >&2; exit 1; }; ONLY_RAW="$2"; ONLY_SEEN=1; shift ;;
  --only=*) ONLY_RAW="${1#*=}"; ONLY_SEEN=1 ;;
  --skip) [[ $# -ge 2 ]] || { echo "--skip requires module names, e.g. --skip tmux" >&2; exit 1; }; SKIP_RAW="$2"; SKIP_SEEN=1; shift ;;
  --skip=*) SKIP_RAW="${1#*=}"; SKIP_SEEN=1 ;;
  -h | --help) usage; exit 0 ;;
  *) echo "unknown arg: $1" >&2; echo "try: $0 --help" >&2; exit 1 ;;
esac; shift; done

# BLIB_DRY must exist before the lib is sourced (the lib reads it with :- defaults,
# so this is belt-and-braces) and is exported so anything we shell out to agrees.
export BLIB_DRY="${BLIB_DRY:-0}"

# ── core/ subtree present? (inline: can't source a lib out of core/ before this) ─
# Validate the SPECIFIC paths we depend on (zsh modules + the two libs sourced
# next) so a missing/partial subtree fails HERE with a precise message, not later
# with a cryptic `source: No such file`.
for _req in core/zsh/loader.zsh core/lib/ux.sh core/lib/bootstrap-lib.sh; do
  if [[ ! -e "$DOTFILES/$_req" ]]; then
    echo "core/ subtree missing or incomplete (need $_req). One-time, run:" >&2
    echo "  git subtree add  --prefix=core <dotfiles-core remote> main --squash   # first time" >&2
    echo "  git subtree pull --prefix=core <dotfiles-core remote> main --squash   # to update" >&2
    exit 1
  fi
done
unset _req

# Shared bash UX palette + provisioning scaffold (vendored under core/lib).
# shellcheck source=core/lib/ux.sh
source "$DOTFILES/core/lib/ux.sh"
# shellcheck source=core/lib/bootstrap-lib.sh
source "$DOTFILES/core/lib/bootstrap-lib.sh"

# Fail LOUD and located. Under `set -e` a mid-run failure used to abort with no
# indication of where — on a fresh box, mid-`pacman`, that is the difference
# between "retry the one step" and "start over".
#
# The BASH_SUBSHELL guard is load-bearing, not defensive: `-E` propagates this trap
# into command/process substitutions, and a perfectly normal `read` returning 1 at
# EOF inside blib_read_pkgs' while-loop runs in the `< <(…)` subshell. Without the
# guard every single run printed a spurious "bootstrap FAILED … IFS= read -r line".
# Only the main shell can actually be failing the bootstrap.
_bootstrap_err() {
  local rc="$1" line="$2" cmd="$3"
  ((BASH_SUBSHELL > 0)) && return 0
  blib_warn "bootstrap FAILED (exit $rc) at ${BASH_SOURCE[0]}:${line}: ${cmd}"
  exit "$rc"
}
trap '_bootstrap_err "$?" "$LINENO" "$BASH_COMMAND"' ERR

# Apply any --only/--skip module selection now the validator (blib_select) exists;
# it aborts on a malformed selector or an unknown group.
if ((ONLY_SEEN)); then blib_select --only "$ONLY_RAW"; fi
if ((SKIP_SEEN)); then blib_select --skip "$SKIP_RAW"; fi
# blib_want treats --only as an allowlist that WINS, so a --skip alongside it is
# silently inert. Say so rather than letting the user believe both applied.
if ((ONLY_SEEN)) && ((SKIP_SEEN)); then
  blib_warn "both --only and --skip given: --only is an allowlist and WINS; --skip '$SKIP_RAW' is ignored"
fi

# ── sanity: confirm we're on Arch ─────────────────────────────────────────────
# Match the ID line specifically so we don't false-positive on a distro that
# merely mentions "arch" in its NAME/pretty string. (ArchWSL keeps ID=arch.)
# Arch DERIVATIVES (EndeavourOS, Manjaro, CachyOS) set their own ID but carry
# ID_LIKE=arch and a working pacman, so they are accepted with a warning rather
# than refused — the package list and every alias in os/arch.zsh still apply.
if ! grep -qE '^ID=arch$' /etc/os-release 2>/dev/null; then
  if grep -qE '^ID_LIKE=.*\barch\b' /etc/os-release 2>/dev/null; then
    blib_warn "not Arch proper, but ID_LIKE=arch (a derivative) — continuing; packages.txt assumes Arch repo names"
  else
    echo "This bootstrap targets Arch Linux. /etc/os-release doesn't look like Arch (no 'ID=arch' or 'ID_LIKE=...arch...')." >&2
    exit 1
  fi
fi

IS_WSL=0
if blib_is_wsl; then IS_WSL=1; fi

provision() {
  # ── Arch golden rule: NEVER partial-upgrade ────────────────────────────────
  # `pacman -Sy <pkg>` (refresh without -u) is the classic Arch footgun: it can
  # pull a package built against newer libs than your unupgraded system has. The
  # correct pattern is a full `-Syu` FIRST so the box is current before installs.
  #
  # Privilege goes through the lib's _blib_priv, NOT a hardcoded `sudo`: that
  # honours BLIB_SU, so this works as root (BLIB_SU=) and on a doas-only box
  # (BLIB_SU=doas). It is also what makes provision() runnable in a container —
  # Arch base images ship no sudo, which is exactly why core's bootstrap-test.yml
  # has to set BLIB_SU= before invoking this script.

  local -a pkgs=()
  mapfile -t pkgs < <(blib_read_pkgs "$DOTFILES/install/packages.txt")
  # blib_read_pkgs' exit status is LOST inside the process substitution, so a
  # missing or empty packages.txt yields an empty array rather than an error. Left
  # unchecked, `pacman -S` with zero targets fails, the per-package fallback loops
  # zero times, and the run reports success having installed NOTHING. Fail here.
  if ((${#pkgs[@]} == 0)); then
    blib_warn "no packages parsed from $DOTFILES/install/packages.txt (missing, empty, or all comments) — refusing to continue"
    exit 1
  fi

  if _blib_dry; then
    blib_say "would run: pacman -Syu, then install ${#pkgs[@]} packages from install/packages.txt"
    blib_say "would install: ${pkgs[*]}"
    # Spelled as `if` blocks, not `((x)) && say …`: under `set -e` + the ERR trap a
    # false guard makes the whole && list return non-zero, which is exactly the kind
    # of "failed but harmless" status this script now reports loudly.
    if ((IS_WSL)); then install_wsl_conf; fi
    if ((DO_FLATPAK)) && ! ((IS_WSL)); then blib_say "would add the Flathub remote"; fi
    return 0
  fi

  blib_say "pacman full system sync + upgrade (-Syu)"
  _blib_priv pacman -Syu --noconfirm

  blib_say "pacman packages (${#pkgs[@]} from install/packages.txt)"
  # Unlike dnf's --skip-unavailable, pacman aborts the WHOLE transaction if any
  # single target name is wrong. Try the bulk install with --needed (skips
  # already-installed), and on failure fall back to a per-package loop so one bad
  # name can't sink the rest. (System is current from -Syu, so -S is not partial.)
  if _blib_priv pacman -S --needed --noconfirm "${pkgs[@]}"; then
    blib_ok "pacman packages installed (${#pkgs[@]} requested)"
  else
    blib_say "bulk install hit a snag — retrying package-by-package (resilient)"
    local p
    for p in "${pkgs[@]}"; do
      # Record rather than discard. Arch is a ROLLING release: packages get
      # renamed and dropped between runs, and a silently-skipped name is how a
      # box ends up missing a tool with a green bootstrap behind it.
      _blib_priv pacman -S --needed --noconfirm "$p" || PROVISION_FAILED+=("$p")
    done
    if ((${#PROVISION_FAILED[@]})); then
      blib_warn "${#PROVISION_FAILED[@]} package(s) failed to install (see the summary at the end)"
    else
      blib_ok "per-package install pass complete (all succeeded)"
    fi
  fi

  # NOTE (vs Fedora): starship, atuin, yazi, mise, lazygit are ALL in Arch's
  # official repos (extra), so they live in packages.txt — no upstream-installer
  # block here. That's the Arch payoff: one package manager, no curl|sh fallbacks.

  # ── the few core-doctor tools NOT in the official repos (AUR / Go) ──────────
  # carapace, sesh, op live only in the AUR (doggo moved into `extra` — it's in
  # packages.txt now). This bootstrap deliberately does NOT build an AUR helper
  # (paru is a documented manual step below), so we install the two Go tools
  # straight from source — best-effort, never fatal under `set -e`. If you
  # already run paru, the native route is:
  #   paru -S carapace-bin sesh-bin 1password-cli
  # NOTE: `go install` drops binaries in $GOBIN (defaults to ~/go/bin), which is
  # NOT on the shell PATH (the Core shell layer prefixes ~/.local/bin + ~/.cargo/
  # bin). Pin GOBIN=~/.local/bin so the tools land somewhere already on PATH.
  #
  # VERSIONS: these default to `latest`, which is NOT reproducible — a re-run six
  # months from now installs different code. Core pins and SHA-256-verifies every
  # tool it downloads (core/scripts/tool-versions.env); this path cannot reuse that
  # machinery because it builds from source rather than fetching a release asset.
  # Pin deliberately by exporting CARAPACE_VERSION / SESH_VERSION (e.g. v1.4.1), or
  # prefer the AUR route above, which is version-controlled by the PKGBUILD.
  local go_log="${TMPDIR:-/tmp}/dotfiles-go-install.$$.log"
  _dotfiles_go_install() { # <import-path> <version> <binary-name>
    [ "$#" -ge 3 ] || return 0
    if command -v "$3" >/dev/null 2>&1; then return 0; fi
    local gobin="$HOME/.local/bin" spec="$1@$2"
    mkdir -p "$gobin" 2>/dev/null || true
    # Errors go to a LOG, not /dev/null. The old form suppressed stderr entirely,
    # so a compile failure surfaced only as a one-line "retry later" hint with no
    # way to find out why it failed.
    if command -v go >/dev/null 2>&1; then
      GOBIN="$gobin" go install "$spec" >>"$go_log" 2>&1 ||
        echo "   $3: go install failed — see $go_log; retry: GOBIN=$gobin go install $spec"
    elif command -v mise >/dev/null 2>&1; then
      GOBIN="$gobin" mise exec go@latest -- go install "$spec" >>"$go_log" 2>&1 ||
        echo "   $3: go install failed — see $go_log; retry: GOBIN=$gobin go install $spec"
    else
      echo "   $3: needs Go — install later with: GOBIN=$gobin go install $spec"
    fi
    return 0
  }
  blib_say "core-doctor extras not in Arch repos (best-effort via Go)"
  _dotfiles_go_install github.com/carapace-sh/carapace-bin/cmd/carapace \
    "${CARAPACE_VERSION:-latest}" carapace
  # /v2 module path is required for sesh
  _dotfiles_go_install github.com/joshmedeski/sesh/v2 "${SESH_VERSION:-latest}" sesh
  # viddy (watch->viddy alias, HAVE_VIDDY-guarded) is a Rust CLI, AUR-only on Arch. This
  # bootstrap builds no AUR helper and installs no rust toolchain (see packages.txt), so
  # it's a manual step — like op below:
  #   paru -S viddy      (or, with a rust toolchain: cargo install viddy)
  if ! command -v viddy >/dev/null 2>&1; then
    echo "   viddy: not found — install the AUR 'viddy' pkg (e.g. 'paru -S viddy')" \
         "for the watch replacement, or 'cargo install viddy' with a rust toolchain"
  fi
  # op (1Password CLI) is proprietary — no Go route. On Arch it's the AUR
  # `1password-cli` package, whose PKGBUILD verifies AgileBits' PGP key
  # 3FEF9748469ADBE15DA7CA80AC2D62742012EA22 (if the build complains, first run:
  #   gpg --recv-keys 3FEF9748469ADBE15DA7CA80AC2D62742012EA22).
  if ! command -v op >/dev/null 2>&1; then
    echo "   op: 1Password CLI not found — install the AUR '1password-cli' pkg" \
         "(e.g. 'paru -S 1password-cli') or see https://developer.1password.com/docs/cli"
  fi

  # ── WSL: install /etc/wsl.conf (systemd + default user + interop) ───────────
  if ((IS_WSL)); then
    install_wsl_conf
  fi

  if ((DO_FLATPAK)) && ! ((IS_WSL)); then
    blib_say "Flathub"
    flatpak remote-add --if-not-exists flathub \
      https://flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 || true
  fi

  # ── Optional, NOT automated (documented manual steps) ──────────────────────
  #  • multilib (32-bit / Wine): uncomment [multilib] in /etc/pacman.conf, then -Syu.
  #  • AUR helper: build paru once (sudo pacman -S --needed base-devel git; then
  #    git clone https://aur.archlinux.org/paru.git && makepkg -si).
  #  • Fastest mirrors: sudo reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist
}

# ── /etc/wsl.conf, written NON-DESTRUCTIVELY ──────────────────────────────────
# This used to be a bare `sed … | sudo tee /etc/wsl.conf`, which clobbered whatever
# was there. Every other mutation in this system backs up first (blib_link moves a
# real file to <dst>.pre-dotfiles.<epoch>), and bootstrap.sh is documented as safe
# to re-run — so a user who had added [automount], [boot] command=, or a hostname
# lost it silently on the second run. Now: no-op when already correct, back up
# otherwise.
install_wsl_conf() {
  local user rendered current="" backup
  user="$(id -un)"
  # Bash string replacement, NOT sed: the username is DATA, and in a sed
  # replacement `&` expands to the whole match and `\` escapes — so a username
  # containing either would be silently mangled. `${var//pat/rep}` has no such
  # metacharacters.
  rendered="$(cat "$DOTFILES/wsl/wsl.conf")"
  rendered="${rendered//__WSL_USER__/$user}"

  [[ -r /etc/wsl.conf ]] && current="$(cat /etc/wsl.conf)"
  if [[ "$current" == "$rendered" ]]; then
    blib_ok "/etc/wsl.conf already current — left alone"
    return 0
  fi

  if _blib_dry; then
    if [[ -e /etc/wsl.conf ]]; then
      blib_say "would back up + rewrite /etc/wsl.conf (default user: $user)"
    else
      blib_say "would write /etc/wsl.conf (default user: $user)"
    fi
    return 0
  fi

  blib_say "installing /etc/wsl.conf (systemd + default user)"
  if [[ -e /etc/wsl.conf ]]; then
    backup="/etc/wsl.conf.pre-dotfiles.$(date +%s)"
    _blib_priv cp -a /etc/wsl.conf "$backup"
    blib_warn "existing /etc/wsl.conf backed up to $backup — re-apply any local settings from it"
  fi
  printf '%s\n' "$rendered" | _blib_priv tee /etc/wsl.conf >/dev/null
  blib_ok "wsl.conf written — run 'wsl.exe --shutdown' from Windows, then reopen, to apply"
}

wire_links() {
  # The shared symlink surface + the Arch OS overlays + the managed .zshrc loader
  # + the default-login-shell switch all live in core/lib/bootstrap-lib.sh.
  blib_link_core "$DOTFILES" "$CONFIG"
  blib_link_os_layer "$DOTFILES" "$CONFIG" arch
  # shellcheck disable=SC2119  # no args is intentional — writes the default module set
  blib_write_zshrc_loader
  blib_set_login_shell
  # Install the local pre-commit hook that refuses commits touching the vendored
  # core/ subtree. core-integrity.yml catches this at PR time; this catches it at
  # COMMIT time, on a fresh clone, before the mistake is ever pushed. Never fatal:
  # the helper returns non-zero when it can't resolve a hooks dir, and a missing
  # guard must not fail a bootstrap.
  _blib_dry || blib_install_core_guard "$DOTFILES" || true
  blib_ok "symlinks wired$(blib_selected_note)"
  blib_wire_summary
}

((LINKS_ONLY)) || provision
wire_links

# ── final report ──────────────────────────────────────────────────────────────
if _blib_dry; then
  blib_ok "dry run complete — nothing was changed. Re-run without --dry-run to apply."
  exit 0
fi

if ((${#PROVISION_FAILED[@]})); then
  blib_warn "bootstrap finished WIRING, but ${#PROVISION_FAILED[@]} package(s) did not install:"
  printf '      %s\n' "${PROVISION_FAILED[@]}" >&2
  blib_warn "on a rolling release this usually means a rename or a drop — check with"
  blib_warn "  pacman -Ss <name>   /   https://archlinux.org/packages/  and update install/packages.txt"
  exit 1
fi

blib_ok "Arch bootstrap complete — open a new shell or: exec zsh"
blib_say "then verify with:  core-doctor    (and  core-version  for the vendored Core)"
