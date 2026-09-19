#!/usr/bin/env bash
# One-click entry: curl -fsSL .../bootstrap.sh | bash
# Ensures git, clones (or fast-forward pulls) ~/dotfiles, execs install.sh.
set -euo pipefail
REPO_URL="https://github.com/iamaamir/dotfiles.git"
REPO_DIR="$HOME/dotfiles"

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
elif [ -e "$REPO_DIR" ]; then
  echo "$REPO_DIR exists and is not a git checkout; move it aside, then re-run." >&2
  exit 1
else
  git clone "$REPO_URL" "$REPO_DIR"
fi
if [ "${BOOTSTRAP_DRY_RUN:-0}" = 1 ]; then exit 0; fi
cd "$REPO_DIR"
exec ./install.sh "$@"
