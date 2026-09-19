#!/usr/bin/env bash
# Stow-free linker. Reads links.txt, symlinks repo files into $HOME.
# Backup-then-link; converged re-runs are no-ops. Pure bash, zero deps.
# Single flag only: --dry-run prints the plan, --verify reports
# OK/MISSING/BROKEN. --help prints usage.
# MANIFEST may be overridden via LINKS_MANIFEST (used by the test suite for
# negative cases); it defaults to links.txt next to this script.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${LINKS_MANIFEST:-$REPO_ROOT/links.txt}"

usage() { echo "usage: link.sh [--dry-run|--verify|--help]"; }

MODE="link"
case "${1:-}" in
  "") ;;
  --dry-run) MODE="dry-run" ;;
  --verify) MODE="verify" ;;
  --help|-h) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || { usage >&2; exit 2; }

[ -f "$MANIFEST" ] && [ -r "$MANIFEST" ] || { echo "MANIFEST-MISSING $MANIFEST" >&2; exit 1; }

# One stamp per run plus PID: every backup from a single run lands in the
# same dir, and concurrent runs never share one.
STAMP="$(date +%Y%m%d-%H%M%S)-$$"

link_one() { # link_one <src-rel> <dest-absolute>
  local src dest rel backup n
  src="$REPO_ROOT/$1"; dest="$2"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    echo "SKIP $dest (already correct)"; return 0
  fi
  if [ "$MODE" = "dry-run" ]; then echo "LINK $dest -> $src"; return 0; fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    rel="${dest#"$HOME"/}"
    backup="$HOME/.dotfiles-backup/$STAMP/$rel"
    n=0
    while [ -e "$backup" ] || [ -L "$backup" ]; do
      n=$((n + 1)); backup="$HOME/.dotfiles-backup/$STAMP/$rel.$n"
    done
    mkdir -p "$(dirname "$backup")"
    echo "BACKUP $dest -> $backup"
    mv "$dest" "$backup"
  fi
  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest"
  echo "LINK $dest -> $src"
}

while read -r src dest extra || [[ -n "$src" ]]; do
  case "$src" in \#*|"") continue ;; esac
  if [[ -n "${extra:-}" ]]; then
    echo "MANIFEST-BAD (extra field): $src $dest $extra" >&2; exit 1
  fi
  if [[ -z "${dest:-}" ]]; then
    echo "MANIFEST-BAD (empty dest): $src" >&2; exit 1
  fi
  case "$dest" in
    \~[!/]*) echo "REFUSE $dest (~user expansion unsupported)" >&2; exit 1 ;;
  esac
  dest="${dest/#\~/$HOME}"
  if [ "$dest" = "$HOME" ] || [ "$dest" = "$HOME/" ]; then
    echo "REFUSE $dest (dest is HOME itself)" >&2; exit 1
  fi
  case "$dest" in
    "$HOME"/*) ;;
    *) echo "REFUSE $dest (outside HOME)" >&2; exit 1 ;;
  esac
  case "$dest" in
    */../*|*/..|../*|..) echo "REFUSE $dest (.. component escapes HOME)" >&2; exit 1 ;;
  esac
  if [ "$MODE" != "verify" ] && [ ! -e "$REPO_ROOT/$src" ]; then
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
