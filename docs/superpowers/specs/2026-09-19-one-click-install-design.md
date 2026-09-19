# One-click dotfiles install (stow-free) — design

Date: 2026-09-19. Status: approved sections 1–4, pending spec review.

## Problem

Setup depends on `stow`: the commands are forgettable magic, and stow itself
must be installed first (chicken-and-egg on a fresh Mac). Goal: one curl-piped
command that takes a brand-new Mac to a fully working shell — configs, aliases,
symlinks — with no stow and no memorized commands.

## Decisions (from brainstorming)

- Target: macOS only (Apple Silicon + Intel via `brew --prefix`).
- Bootstrap: `curl -fsSL .../bootstrap.sh | bash`, zero prerequisites.
- Conflicts: backup-then-link to `~/.dotfiles-backup/<timestamp>/`, never
  overwrite, never delete.
- Secrets: stub `zsh/privatealiases.zsh` from a committed
  `zsh/privatealiases.zsh.example` template when missing.
- Testing must clean up after itself (sandbox HOME removed, no /tmp litter).

## Approach (chosen: A — manifest + tiny linker + curl bootstrap)

Rejected: B (convention-mirror collapses into special cases for this layout),
C (keep stow — violates the stated constraint).

## 1. The one command

`curl -fsSL https://raw.githubusercontent.com/iamaamir/dotfiles/main/bootstrap.sh | bash`

`bootstrap.sh` is thin and curl-pipe-safe: `set -euo pipefail`, no prompts
before the repo is on disk. It ensures `git` (missing → `xcode-select
--install`, then re-exec), clones to `~/dotfiles` (or `git pull --ff-only` if
present), then execs `./install.sh`. All flags pass through
(`--dry-run`, `--verify`).

## 2. Manifest + linker

`links.txt` at repo root, one `<repo-rel-path>  <home-rel-path>` mapping per
line, `#` comments, `~` allowed on the destination side. Files that are
sourced (not linked) get no line. Initial inventory (finalized at
implementation): `zsh/.zshrc → ~/.zshrc`, `zsh/.zshenv → ~/.zshenv`
(reconciles the currently unreferenced repo copy), `.config/starship.toml`,
`.config/wezterm-config`, `.config/tmux`, `.config/nvim` (submodule: linked,
never written), plus `vimrc`, `wget`, `kitty`, `iterm2`, `raycast`, `git`,
`firefox`, `argoq` entries per whatever stow links today.

`link.sh` (pure bash, zero deps) per line: dest already correct → skip; dest
exists otherwise → move to `~/.dotfiles-backup/<timestamp>/` preserving
structure; `ln -s` (creating parent dirs). Flags: `--dry-run` prints the
plan, `--verify` reports OK/MISSING/BROKEN per line. Converged re-runs are
no-ops.

## 3. Install chain (`install.sh`, each step a guarded no-op on re-run)

1. CLT check → brew check (existing logic kept).
2. `brew.sh` packages (the `brew install stow` line is deleted).
3. `link.sh` (passthrough: `install.sh --dry-run` prints the whole plan).
4. `link.sh --verify` post-install confidence check.
5. Secrets stub from `zsh/privatealiases.zsh.example` when missing.
6. Live smoke: `zsh -n ~/.zshrc` + silent-source check (regression seam from
   the `ghbrowse` boot-noise bug).
7. Default shell to zsh if needed; closing summary: linked files, backup
   location, stubbed secrets to fill in.

`ssh.sh` stays a separate explicit step (needs your email; never unattended).

## 4. Testing, edge cases, cleanup

- Sandbox test: `HOME=$(mktemp -d) ./install.sh`; assert every manifest dest
  resolves, boot smoke passes, and a second run is a byte-identical no-op.
- Edge cases: existing `~/dotfiles` (pull, don't clone), clashing dests
  (backup), Intel vs Silicon brew prefix, `~/.zshenv` drift resolved by the
  manifest entry.
- Cleanup (required): the test harness removes the sandbox HOME and all temp
  fixtures on success AND failure (`trap ... EXIT INT TERM`); the installer
  itself leaves no temp files behind. Verified by asserting an empty
  before/after file list in the sandbox parent.
- Existing `gptcommit` suite stays green; no changes to shell runtime files
  beyond deletions/additions listed above.
