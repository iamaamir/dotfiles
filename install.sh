#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#install brew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

#install brew packages (repo-root independent)
"$SCRIPT_DIR/brew.sh"

# kitty (skip when already installed)
if ! command -v kitty >/dev/null 2>&1; then
  curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
fi

# all clones goest here
mkdir -p ~/git

echo "upnext run 'sh ./ssh.sh <email@xyz.com>' to generate ssh key"
