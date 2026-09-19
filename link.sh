#!/usr/bin/env bash
# Stow-free linker. Reads links.txt, symlinks repo files into $HOME.
# Backup-then-link; converged re-runs are no-ops. Pure bash, zero deps.
# Only a single flag is supported (--dry-run or --verify, never combined).
# MANIFEST may be overridden via LINKS_MANIFEST (used by the test suite for
# negative cases); it defaults to links.txt next to this script.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${LINKS_MANIFEST:-$REPO_ROOT/links.txt}"

usage() { echo "usage: link.sh [--dry-run|--verify]" >&2; }

MODE="link"
case "${1:-}" in
  "") ;;
  --dry-run) MODE="dry-run" ;;
  --verify) MODE="verify" ;;
  *) usage; exit 2 ;;
esac

link_one() { # link_one <src-rel> <dest-absolute>
  local src="$REPO_ROOT/$1" dest="$2"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    echo "SKIP $dest (already correct)"; return 0
  fi
  if [ "$MODE" = "dry-run" ]; then echo "LINK $dest -> $src"; return 0; fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    local rel="${dest#$HOME/}"
    local backup="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)/$rel"
    mkdir -p "$(dirname "$backup")"
    echo "BACKUP $dest -> $backup"
    mv "$dest" "$backup"
  fi
  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest"
  echo "LINK $dest -> $src"
}

while read -r src dest; do
  case "$src" in \#*|"") continue ;; esac
  dest="${dest/#\~/$HOME}"
  case "$dest" in
    "$HOME"/*) ;;
    *) echo "REFUSE $dest (outside HOME)" >&2; exit 1 ;;
  esac
  if [ ! -e "$REPO_ROOT/$src" ]; then
    echo "SRC-MISSING $REPO_ROOT/$src" >&2; exit 1
  fi
  if [ "$MODE" = "verify" ]; then
    want="$REPO_ROOT/$src"
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$want" ] && [ -e "$dest" ]; then
      echo "OK $dest"
    elif [ -e "$dest" ] || [ -L "$dest" ]; then
      echo "BROKEN $dest (-> $(readlink "$dest" 2>/dev/null))"; VERIFY_RC=1
    else
      echo "MISSING $dest"; VERIFY_RC=1
    fi
    continue
  fi
  link_one "$src" "$dest"
done < "$MANIFEST"

if [ "$MODE" = "verify" ]; then
  exit "${VERIFY_RC:-0}"
fi
