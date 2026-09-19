#!/usr/bin/env bash
# Sandbox suite for the one-click installer. Never touches the live $HOME.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-sandbox-XXXXXXXX")"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT INT TERM
export INSTALL_SANDBOX=1 HOME="$SANDBOX"
[ "${VERBOSE:-0}" = 1 ] && echo "SANDBOX=$SANDBOX"

PASS=0; FAIL=0
t() { # t <name> <command...>: records PASS/FAIL, never aborts the suite
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "ok   $name";
  else FAIL=$((FAIL+1)); echo "FAIL $name"; fi
}

t "manifest exists" test -f "$REPO_ROOT/links.txt"
t "manifest has 6 mappings" test "$(grep -cvE '^\s*(#|$)' "$REPO_ROOT/links.txt")" -eq 6
t "link.sh exists and is executable" test -x "$REPO_ROOT/link.sh"
t "fresh link creates ~/.zshrc symlink" bash -c '
  HOME="$0" "$1/link.sh" >/dev/null 2>&1 &&
  [ -L "$0/.zshrc" ] && [ "$(readlink "$0/.zshrc")" = "$1/zsh/.zshrc" ]' "$SANDBOX" "$REPO_ROOT"
t "all 6 manifest dests resolve" bash -c '
  HOME="$0" "$1/link.sh" >/dev/null 2>&1 &&
  while read -r src dest; do case "$src" in \#*|"") continue;; esac
    dest="${dest/#\~/$0}"
    [ -e "$dest" ] || exit 1
  done < "$1/links.txt"' "$SANDBOX" "$REPO_ROOT"
t "clash is backed up, not overwritten" bash -c '
  d="$0/clash"; mkdir -p "$d" &&
  echo original > "$d/.zshrc" &&
  HOME="$d" "$1/link.sh" >/dev/null 2>&1 &&
  [ -L "$d/.zshrc" ] &&
  grep -rq original "$d/.dotfiles-backup/"' "$SANDBOX" "$REPO_ROOT"
t "second run is a no-op (all SKIP)" bash -c '
  d="$0/noop"; mkdir -p "$d" &&
  HOME="$d" "$1/link.sh" >/dev/null 2>&1 &&
  [ -z "$(HOME="$d" "$1/link.sh" 2>&1 | grep -v "^SKIP ")" ]' "$SANDBOX" "$REPO_ROOT"
t "dry-run changes nothing" bash -c '
  d="$0/dry"; mkdir -p "$d" &&
  HOME="$d" "$1/link.sh" --dry-run >/dev/null 2>&1 &&
  [ ! -e "$d/.zshrc" ] && [ ! -d "$d/.dotfiles-backup" ]' "$SANDBOX" "$REPO_ROOT"
t "verify reports all OK" bash -c '
  d="$0/verify"; mkdir -p "$d" &&
  HOME="$d" "$1/link.sh" >/dev/null 2>&1 &&
  HOME="$d" "$1/link.sh" --verify 2>&1 | grep -q "^OK"' "$SANDBOX" "$REPO_ROOT"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
