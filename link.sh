#!/usr/bin/env bash
# Stow-free linker. Reads links.txt, symlinks repo files into $HOME.
# Backup-then-link; converged re-runs are no-ops. Pure bash, zero deps.
# Single flag only: --dry-run prints the plan, --verify reports
# OK/MISSING/BROKEN. --help prints usage.
# MANIFEST may be overridden via LINKS_MANIFEST (used by the test suite for
# negative cases); it defaults to links.txt next to this script.
set -euo pipefail
set -f # no pathname expansion anywhere below: manifest/HOME may contain glob chars
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$REPO_ROOT/links.txt"
# Test seam, sandbox-only: a stale global export must never redirect
# production runs (round-7 finding).
if [ "${INSTALL_SANDBOX:-0}" = 1 ] && [ -n "${LINKS_MANIFEST:-}" ]; then
  MANIFEST="$LINKS_MANIFEST"
fi

usage() { echo "usage: link.sh [--dry-run|--verify|--help]"; }

MODE="link"
case "${1:-}" in
  "") [ "$#" -eq 0 ] || { usage >&2; exit 2; } ;;
  --dry-run) MODE="dry-run" ;;
  --verify) MODE="verify" ;;
  --help|-h) [ "$#" -le 1 ] || { usage >&2; exit 2; }; usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || { usage >&2; exit 2; }

[ -f "$MANIFEST" ] && [ -r "$MANIFEST" ] || { echo "MANIFEST-MISSING $MANIFEST" >&2; exit 1; }

# One stamp per run plus PID: every backup from a single run lands in the
# same dir, and concurrent runs never share one.
STAMP="$(date +%Y%m%d-%H%M%S)-$$"

normalize() { # normalize <abs-path>: lexical . and .. resolution, no fs access
  local p="$1" out comp
  out=""
  local IFS='/'
  for comp in $p; do
    case "$comp" in
      ""|.) continue ;;
      ..) out="${out%/*}" ;;
      *) out="$out/$comp" ;;
    esac
  done
  printf '%s' "${out:-/}"
}

# Canonical HOME: normalized once so `//` (e.g. macOS TMPDIR) and trailing
# slashes cannot desync textual paths from containment checks below.
: "${HOME:?HOME must be set}"
HOME="$(normalize "$HOME")"
HN="$HOME"

under_home() { # under_home <abs-path>: 0 iff path equals $HN or starts
               # with $HN/ — literal substring compare, so glob chars in
               # $HOME cannot change the semantics
  local p="$1" n=${#HN}
  [ "${p:0:n}" = "$HN" ] && { [ "${#p}" -eq "$n" ] || [ "${p:n:1}" = "/" ]; }
}

no_escape() { # no_escape <abs-path>: 0 iff no strict parent dir of path
              # (from $HOME down) is a symlink escaping $HOME. Symlinks
              # pointing inside $HOME are followed (lived-in Macs).
  local target="$1" parent rel cur comp tgt norm n
  under_home "$target" || { echo "REFUSE $target (outside HOME)" >&2; return 1; }
  parent="$(dirname "$target")"
  [ "$parent" = "$HN" ] && return 0
  rel="${parent:${#HN}+1}"
  cur="$HOME"
  local IFS='/'
  for comp in $rel; do
    cur="$cur/$comp"
    n=0
    while [ -L "$cur" ]; do
      n=$((n + 1))
      if [ "$n" -gt 40 ]; then
        echo "REFUSE $target (symlink loop at $cur)" >&2; return 1
      fi
      tgt="$(readlink "$cur")"
      case "$tgt" in
        /*) norm="$(normalize "$tgt")" ;;
        *) norm="$(normalize "$(dirname "$cur")/$tgt")" ;;
      esac
      if under_home "$norm"; then cur="$norm"; else
        echo "REFUSE $target (symlink parent $cur escapes HOME)" >&2; return 1
      fi
    done
  done
  return 0
}

link_one() { # link_one <src-rel> <dest-absolute>
  local src dest rel backup n
  src="$REPO_ROOT/$1"; dest="$2"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    echo "SKIP $dest (already correct)"; return 0
  fi
  if [ "$MODE" = "dry-run" ]; then echo "LINK $dest -> $src"; return 0; fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    rel="${dest:${#HN}+1}"
    backup="$HOME/.dotfiles-backup/$STAMP/$rel"
    n=0
    while [ -e "$backup" ] || [ -L "$backup" ]; do
      n=$((n + 1)); backup="$HOME/.dotfiles-backup/$STAMP/$rel.$n"
    done
    no_escape "$backup" || return 1
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
  case "$src" in
    /*|*/../*|*/..|../*|..) echo "REFUSE $src (src escapes repo)" >&2; exit 1 ;;
  esac
  case "$dest" in
    \~[!/]*) echo "REFUSE $dest (~user expansion unsupported)" >&2; exit 1 ;;
  esac
  dest="${dest/#\~/$HOME}"
  case "$dest" in
    */../*|*/..|../*|..) echo "REFUSE $dest (.. component escapes HOME)" >&2; exit 1 ;;
  esac
  dest="$(normalize "$dest")"
  if [ "$dest" = "$HN" ]; then
    echo "REFUSE $dest (dest is HOME itself)" >&2; exit 1
  fi
  under_home "$dest" || { echo "REFUSE $dest (outside HOME)" >&2; exit 1; }
  no_escape "$dest" || exit 1
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
