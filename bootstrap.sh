#!/usr/bin/env bash
# One-click entry: curl -fsSL .../bootstrap.sh | bash
# Ensures git, clones (or fast-forward pulls) ~/dotfiles with submodules,
# then execs install.sh. Flags pass through to install.sh.
set -euo pipefail
REPO_URL="https://github.com/iamaamir/dotfiles.git"
REPO_DIR="$HOME/dotfiles"

usage() { echo "usage: bootstrap.sh [--dry-run|--verify|--help]"; echo "(clones/pulls ~/dotfiles first; flags govern the install phase. BOOTSTRAP_DRY_RUN=1 stops after clone/pull.)"; }

nflags=0; wanthelp=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|--verify) nflags=$((nflags + 1)) ;;
    --help|-h) wanthelp=1 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[ "$nflags" -le 1 ] || { usage >&2; exit 2; }
if [ "$wanthelp" = 1 ]; then
  [ "$#" -eq 1 ] || { usage >&2; exit 2; }
  usage; exit 0
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git not found — triggering Xcode CLT install (opens a macOS dialog)."
  xcode-select --install || true
  echo "Re-run the one-line installer after the CLT finishes."
  exit 1
fi
if [ -d "$REPO_DIR/.git" ]; then
  git -C "$REPO_DIR" pull --ff-only || {
    echo "git pull --ff-only failed (diverged?); cd $REPO_DIR and reconcile, then re-run." >&2
    exit 1
  }
  git -C "$REPO_DIR" submodule update --init --recursive || {
    echo "submodule update failed in $REPO_DIR; cd there and fix, then re-run." >&2
    exit 1
  }
elif [ -e "$REPO_DIR" ]; then
  echo "$REPO_DIR exists and is not a git checkout; move it aside, then re-run." >&2
  exit 1
else
  git clone --recurse-submodules "$REPO_URL" "$REPO_DIR" || {
    echo "git clone failed (network? auth?); check connectivity and re-run the one-line installer." >&2
    exit 1
  }
fi
if [ "${BOOTSTRAP_DRY_RUN:-0}" = 1 ]; then exit 0; fi
cd "$REPO_DIR"
exec ./install.sh "$@"
