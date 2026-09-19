#!/usr/bin/env bash
# One-click dotfiles install. Idempotent: safe to re-run any time.
# Flags pass through to link.sh: --dry-run, --verify.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANDBOX="${INSTALL_SANDBOX:-}"

if [ -z "$SANDBOX" ]; then
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

# all clones goest here
mkdir -p ~/git

# symlinks from the manifest (backup-then-link; --dry-run/--verify pass through)
"$SCRIPT_DIR/link.sh" "$@"

# secrets stub so sourcing never breaks on a fresh clone
if [ ! -f "$SCRIPT_DIR/zsh/privatealiases.zsh" ]; then
  cp "$SCRIPT_DIR/zsh/privatealiases.zsh.example" "$SCRIPT_DIR/zsh/privatealiases.zsh"
  echo "STUB zsh/privatealiases.zsh (fill in your keys)"
fi

# smoke: linked shell must parse (skipped for --dry-run: nothing is linked yet)
case " $* " in
  *" --dry-run "*) echo "SMOKE skipped (--dry-run)" ;;
  *) zsh -n "$HOME/.zshrc" && echo "SMOKE zsh -n ~/.zshrc OK" ;;
esac

if [ -z "$SANDBOX" ]; then
  if [[ "$SHELL" != *zsh ]]; then
    echo "Switching default shell to zsh (needs password once)."
    chsh -s /bin/zsh
  fi
fi

echo "upnext run 'sh ./ssh.sh <email@xyz.com>' to generate ssh key"
