#!/usr/bin/env bash
# Stow-free linker. Reads links.txt, symlinks repo files into $HOME.
# Backup-then-link; converged re-runs are no-ops. Pure bash, zero deps.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$REPO_ROOT/links.txt"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

if [ "${1:-}" = "--verify" ]; then
  rc=0
  while read -r src dest; do
    case "$src" in \#*|"") continue ;; esac
    dest="${dest/#\~/$HOME}"; want="$REPO_ROOT/$src"
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$want" ]; then echo "OK $dest";
    elif [ -e "$dest" ] || [ -L "$dest" ]; then echo "BROKEN $dest (-> $(readlink "$dest" 2>/dev/null))"; rc=1;
    else echo "MISSING $dest"; rc=1; fi
  done < "$MANIFEST"
  exit "$rc"
fi

link_one() { # link_one <src-rel> <dest-absolute>
  local src="$REPO_ROOT/$1" dest="$2"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    echo "SKIP $dest (already correct)"; return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then echo "LINK $dest -> $src"; return 0; fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    local backup="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup"
    echo "BACKUP $dest -> $backup/"
    mv "$dest" "$backup/"
  fi
  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest"
  echo "LINK $dest -> $src"
}

while read -r src dest; do
  case "$src" in \#*|"") continue ;; esac
  link_one "$src" "${dest/#\~/$HOME}"
done < "$MANIFEST"
