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

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
