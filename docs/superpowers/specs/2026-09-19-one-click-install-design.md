# One-click dotfiles install (stow-free) — design

Date: 2026-09-19. Status: approved sections 1–4, pending spec review.
Amendments: 2026-09-19 (review round — manifest scope locked, flag semantics,
test seams documented).

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
no-ops. Single flag only; unknown flags exit 2 with usage. Dests outside
`$HOME` are refused; missing repo sources abort the run (link/dry-run) or
report BROKEN (verify, which also requires the link target to exist —
dangling symlinks are BROKEN, never OK).

Manifest scope (locked): the 6 shipped entries are exact stow parity — that
is all stow links today. The rest of the repo is deliberately NOT in the
manifest: `vimrc/.vimrc` + `wget/.wgetrc` (absent from $HOME today; linking
them would newly activate configs the machine doesn't use — behavior change,
not parity), `git/.gitconfig` (would add a config layer under the
`GIT_CONFIG_GLOBAL`-pointed repo file — pointless and risky), `kitty/`
(empty dir in repo), `iterm2/profile.json` + `raycast/` scripts (imported
through app UIs, not symlinks), `firefox/userChrome.css` (target is a
machine-specific Firefox profile path — cannot be a static entry), `argoq/`
+ `gh/alias.yml` (executed/imported, not linked). Adding any of these later
is a separate decision, not a bug.

## 3. Install chain (`install.sh`, each step a guarded no-op on re-run)

1. CLT check → brew check (existing logic kept).
2. `brew.sh` packages (the `brew install stow` line is deleted).
3. `link.sh` — plus flag branches: `--dry-run` prints the whole plan and
   exits before ANY mutation (no `~/git`, no stub, no smoke, no links);
   `--verify` checks state without linking (no `mkdir`, no stub, no smoke,
   no chsh) and preserves the verify exit code.
4. `link.sh --verify` post-install confidence check inside `install.sh`
   (aborts the chain on failure); OK count feeds the closing summary.
5. Secrets stub from `zsh/privatealiases.zsh.example` when missing.
6. Live smoke: `zsh -n ~/.zshrc` + silent-source check (regression seam from
   the `ghbrowse` boot-noise bug); any output or nonzero exit fails the run.
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
- Test-only seams (never set in production): `BOOTSTRAP_DRY_RUN=1` stops
  bootstrap after clone/pull; `INSTALL_SANDBOX=1` skips brew/kitty/chsh so
  the suite runs without touching the machine; `INSTALL_TEST_NESTED=1`
  stops the suite re-nesting itself; `LINKS_MANIFEST` points the linker at
  an alternate manifest for negative tests.
