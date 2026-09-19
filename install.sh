#!/usr/bin/env bash
# One-click dotfiles install. Idempotent: safe to re-run any time.
# Single flag only: --dry-run prints the plan without changing anything,
# --verify checks the current state without linking.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANDBOX="${INSTALL_SANDBOX:-}"

usage() { echo "usage: install.sh [--dry-run|--verify|--help]"; }

DRY_RUN=0; VERIFY_ONLY=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  --verify) VERIFY_ONLY=1 ;;
  --help|-h) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || { usage >&2; exit 2; }

if [ -z "$SANDBOX" ] && [ "$DRY_RUN" = 0 ] && [ "$VERIFY_ONLY" = 0 ]; then
  #install brew (skip when already installed: re-running pays the full
  # installer on every clone refresh and aborts under set -euo on hiccups)
  if ! command -v brew >/dev/null 2>&1; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  #install brew packages (repo-root independent)
  "$SCRIPT_DIR/brew.sh"

  # kitty (skip when already installed)
  if ! command -v kitty >/dev/null 2>&1; then
    curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
  fi
fi

if [ "$DRY_RUN" = 1 ]; then
  # Plan only: the linker prints every action, nothing else runs.
  "$SCRIPT_DIR/link.sh" --dry-run
  echo "DRY-RUN: no changes made (no symlinks, dirs, stubs, or shell changes)"
  echo "up next, run './install.sh' to apply, 'sh ./ssh.sh <email@xyz.com>' for ssh keys"
  exit 0
fi

if [ "$VERIFY_ONLY" = 0 ]; then
  # symlinks from the manifest (backup-then-link); ~/git only after the
  # links succeed so a link abort leaves no partial mutation behind
  "$SCRIPT_DIR/link.sh"
  # all clones go here
  mkdir -p "$HOME/git"
fi

# secrets stub so sourcing never breaks on a fresh clone
if [ ! -f "$SCRIPT_DIR/zsh/privatealiases.zsh" ]; then
  if [ "$VERIFY_ONLY" = 0 ]; then
    cp "$SCRIPT_DIR/zsh/privatealiases.zsh.example" "$SCRIPT_DIR/zsh/privatealiases.zsh"
    STUB_MSG="created from example (fill in your keys)"
  else
    STUB_MSG="missing (--verify does not create it)"
  fi
else
  STUB_MSG="present"
fi

# post-install confidence check: every manifest dest must resolve
verify_rc=0
verify_out="$("$SCRIPT_DIR/link.sh" --verify 2>&1)" || verify_rc=$?
printf '%s\n' "$verify_out"
if [ "$verify_rc" -ne 0 ]; then
  echo "VERIFY FAILED (rc=$verify_rc) — fix the lines above and re-run" >&2
  exit "$verify_rc"
fi
ok_count="$(printf '%s\n' "$verify_out" | grep -c '^OK ' || true)"

# smoke: linked shell must parse AND source silently (boot-noise regression
# seam: a sourcing .zshrc must produce zero output on a healthy machine).
# Skipped for --verify: that branch is a pure state check (verify rc only).
if [ "$VERIFY_ONLY" = 0 ]; then
  zsh -n "$HOME/.zshrc" || { echo "SMOKE FAIL: zsh -n ~/.zshrc" >&2; exit 1; }
  smoke_rc=0
  smoke_out="$(zsh -c 'source "$HOME/.zshrc"' 2>&1)" || smoke_rc=$?
  if [ "$smoke_rc" -ne 0 ] || [ -n "$smoke_out" ]; then
    echo "SMOKE FAIL: sourcing ~/.zshrc rc=$smoke_rc output:" >&2
    printf '%s\n' "$smoke_out" >&2
    echo "hint: the checkout must live at ~/dotfiles (sourcing hardcodes that path)" >&2
    exit 1
  fi
  echo "SMOKE ~/.zshrc parses + sources silently OK"
else
  echo "SMOKE skipped (--verify: state check only)"
fi

if [ -z "$SANDBOX" ] && [ "$VERIFY_ONLY" = 0 ]; then
  if [[ "${SHELL:-}" != *zsh ]]; then
    echo "Switching default shell to zsh (needs password once)."
    chsh -s /bin/zsh
  fi
fi

# closing summary (no `ls` globs: an empty backup dir must not fail the run)
backup_dir=""
if [ -d "$HOME/.dotfiles-backup" ]; then
  shopt -s nullglob
  for d in "$HOME"/.dotfiles-backup/*/; do
    [[ -z "$backup_dir" || "$d" > "$backup_dir" ]] && backup_dir="$d"
  done
  shopt -u nullglob
fi
[ -z "$backup_dir" ] && backup_dir="none"
echo "DONE: $ok_count links OK; backups: $backup_dir; secrets stub: $STUB_MSG"
echo "up next, run 'sh ./ssh.sh <email@xyz.com>' to generate ssh key"
