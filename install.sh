#!/usr/bin/env bash
# One-click dotfiles install. Idempotent: safe to re-run any time.
# Single flag only: --dry-run prints the plan without changing anything,
# --verify checks the current state without linking.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANDBOX="${INSTALL_SANDBOX:-}"

DRY_RUN=0; VERIFY_ONLY=0
case " $* " in
  *" --dry-run "*) DRY_RUN=1 ;;
  *" --verify "*) VERIFY_ONLY=1 ;;
esac

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
  echo "upnext run './install.sh' to apply, 'sh ./ssh.sh <email@xyz.com>' for ssh keys"
  exit 0
fi

if [ "$VERIFY_ONLY" = 0 ]; then
  # all clones goest here
  mkdir -p ~/git

  # symlinks from the manifest (backup-then-link)
  "$SCRIPT_DIR/link.sh"
fi

# secrets stub so sourcing never breaks on a fresh clone
STUB_MSG="present"
if [ "$VERIFY_ONLY" = 0 ] && [ ! -f "$SCRIPT_DIR/zsh/privatealiases.zsh" ]; then
  cp "$SCRIPT_DIR/zsh/privatealiases.zsh.example" "$SCRIPT_DIR/zsh/privatealiases.zsh"
  STUB_MSG="created from example (fill in your keys)"
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
# seam: a sourcing .zshrc must produce zero output on a healthy machine)
zsh -n "$HOME/.zshrc" || { echo "SMOKE FAIL: zsh -n ~/.zshrc" >&2; exit 1; }
smoke_rc=0
smoke_out="$(zsh -c 'source "$HOME/.zshrc"' 2>&1)" || smoke_rc=$?
if [ "$smoke_rc" -ne 0 ] || [ -n "$smoke_out" ]; then
  echo "SMOKE FAIL: sourcing ~/.zshrc rc=$smoke_rc output:" >&2
  printf '%s\n' "$smoke_out" >&2
  exit 1
fi
echo "SMOKE ~/.zshrc parses + sources silently OK"

if [ -z "$SANDBOX" ] && [ "$VERIFY_ONLY" = 0 ]; then
  if [[ "$SHELL" != *zsh ]]; then
    echo "Switching default shell to zsh (needs password once)."
    chsh -s /bin/zsh
  fi
fi

# closing summary
backup_dir="none"
if [ -d "$HOME/.dotfiles-backup" ]; then
  backup_dir="$(ls -dt "$HOME"/.dotfiles-backup/*/ | head -n 1)"
fi
echo "DONE: $ok_count links OK; backups: $backup_dir; secrets stub: $STUB_MSG"
echo "upnext run 'sh ./ssh.sh <email@xyz.com>' to generate ssh key"
