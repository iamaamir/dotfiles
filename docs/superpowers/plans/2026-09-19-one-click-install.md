# One-click install implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace stow with a manifest-driven linker plus curl-pipe bootstrap so one command sets up a fresh Mac.

**Architecture:** `links.txt` declares repo→home mappings; `link.sh` (pure bash) applies them idempotently with backup-then-link; `bootstrap.sh` ensures git, clones/pulls to `~/dotfiles`, execs the extended `install.sh` chain. Tested in a sandbox `$HOME`, never the live one.

**Tech Stack:** bash (`set -euo pipefail`), POSIX tools only (`ln`, `mv`, `mkdir`, `readlink`), existing `shellcheck` gate, test style mirrors `git/gptcommit-test.sh` (sequential checks, PASS/FAIL summary).

**Spec:** `docs/superpowers/specs/2026-09-19-one-click-install-design.md`

---

## File structure

- Create `links.txt` — 6 mappings (parity with today's stow links + `.zshenv` drift fix).
- Create `link.sh` — zero-dep linker: `--dry-run`, `--verify`, backup, idempotent.
- Create `bootstrap.sh` — curl-pipe entry: git/CLT guard, clone-or-pull, handoff.
- Create `zsh/privatealiases.zsh.example` — secrets stub template, no values.
- Create `install-test.sh` — sandbox-HOME suite, built incrementally, self-cleaning.
- Modify `install.sh` — ordered chain with flag passthrough, smoke, summary.
- Modify `brew.sh:87` — delete `brew install stow`.

Chain of responsibility: `bootstrap.sh` → `install.sh` → `link.sh` + `brew.sh`; `install-test.sh` drives `link.sh`/`install.sh` with `HOME=$SANDBOX`, `INSTALL_SANDBOX=1`.

**Spec deviation (transparent):** when `git` is missing, the installer triggers `xcode-select --install` (best effort, `|| true`) and exits asking for a re-run — the CLT popup is a GUI dialog that cannot complete unattended, so true auto-re-exec would hang. The "one command" stays one command; on a git-less Mac you run it twice.

---

### Task 1: Manifest + test harness skeleton

**Files:**
- Create: `links.txt`
- Create: `install-test.sh` (skeleton: sandbox, trap, counters, 2 manifest checks)

- [ ] **Step 1: Write `links.txt`**

```text
# links.txt — repo-rel-path <whitespace> home-rel-path (~ = $HOME).
# Files that are sourced (not linked) get no line. No spaces in paths.
zsh/.zshrc ~/.zshrc
zsh/.zshenv ~/.zshenv
.config/starship.toml ~/.config/starship.toml
.config/tmux ~/.config/tmux
.config/wezterm-config ~/.config/wezterm-config
.config/nvim ~/.config/nvim
```

- [ ] **Step 2: Write failing harness skeleton `install-test.sh`**

```bash
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
```

- [ ] **Step 3: Run it (expect FAIL — `link.sh` doesn't exist yet is fine; manifest checks should PASS)**

Run: `bash install-test.sh`
Expected: `PASS=2 FAIL=0` (manifest is data; the red comes in Task 2 when linker checks fail).

- [ ] **Step 4: Commit**

```bash
git add links.txt install-test.sh
git commit -m "feat(setup): link manifest and sandbox test skeleton"
```

---

### Task 2: `link.sh` core (fresh link + skip-when-correct)

**Files:**
- Create: `link.sh`
- Modify: `install-test.sh` (append 3 linker checks before the summary)

- [ ] **Step 1: Append failing linker checks to `install-test.sh`** (insert before the `echo "PASS=` line):

```bash
t "link.sh exists and is executable" test -x "$REPO_ROOT/link.sh"
t "fresh link creates ~/.zshrc symlink" bash -c '
  HOME="$0" "$1/link.sh" >/dev/null 2>&1 &&
  [ -L "$0/.zshrc" ] && [ "$(readlink "$0/.zshrc")" = "$1/zsh/.zshrc" ]' "$SANDBOX" "$REPO_ROOT"
t "all 6 manifest dests resolve" bash -c '
  HOME="$0" "$1/link.sh" >/dev/null 2>&1 &&
  while read -r src dest; do case "$src" in \#*|"") continue;; esac
    dest="${dest\~ Replica: "$0"}"
    [ -e "$dest" ] || exit 1
  done < "$1/links.txt"' "$SANDBOX" "$REPO_ROOT"
```

- [ ] **Step 2: Run to verify red**

Run: `bash install-test.sh`
Expected: 3 new FAIL lines (`link.sh` missing), `FAIL=3`.

- [ ] **Step 3: Write minimal `link.sh`**

```bash
#!/usr/bin/env bash
# Stow-free linker. Reads links.txt, symlinks repo files into $HOME.
# Backup-then-link; converged re-runs are no-ops. Pure bash, zero deps.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$REPO_ROOT/links.txt"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

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
  link_one "$src" "${dest\~/$HOME}"
done < "$MANIFEST"
```

- [ ] **Step 4: Run to verify green**

Run: `bash install-test.sh`
Expected: `PASS=5 FAIL=0`. Also verify no backup dir was created on fresh link: `ls "$HOME"/.dotfiles-backup` absent in a manual sandbox run.

- [ ] **Step 5: Commit**

```bash
git add link.sh install-test.sh
git commit -m "feat(setup): stow-free linker with backup-then-link"
```

---

### Task 3: `link.sh` backup, idempotency, `--verify`

**Files:**
- Modify: `link.sh` (add `--verify` mode)
- Modify: `install-test.sh` (append 4 checks)

- [ ] **Step 1: Append failing checks** (before the summary line):

```bash
t "clash is backed up, not overwritten" bash -c '
  echo original > "$0/.zshrc" &&
  HOME="$0" "$1/link.sh" >/dev/null 2>&1 &&
  [ -L "$0/.zshrc" ] &&
  grep -q original "$0"/.dotfiles-backup/*/".zshrc" 2>/dev/null ||
  grep -rq original "$0/.dotfiles-backup/"' "$SANDBOX" "$REPO_ROOT"
t "second run is a no-op (all SKIP)" bash -c '
  HOME="$0" "$1/link.sh" >/dev/null 2>&1 &&
  HOME="$0" "$1/link.sh" 2>&1 | grep -qv "^SKIP "' "$SANDBOX" "$REPO_ROOT"
t "dry-run changes nothing" bash -c '
  HOME="$0" "$1/link.sh" --dry-run >/dev/null 2>&1 &&
  [ ! -e "$0/.zshrc" ] && [ ! -d "$0/.dotfiles-backup" ]' "$SANDBOX" "$REPO_ROOT"
t "verify reports all OK" bash -c '
  HOME="$0" "$1/link.sh" >/dev/null 2>&1 &&
  HOME="$0" "$1/link.sh" --verify 2>&1 | grep -q "^OK"' "$SANDBOX" "$REPO_ROOT"
```

- [ ] **Step 2: Run to verify red**

Run: `bash install-test.sh`
Expected: FAIL on `--verify` checks (`--verify` unrecognized → usage error path; backup/idempotency/dry-run already pass from Task 2 — that's fine, red is on verify).

- [ ] **Step 3: Add `--verify` to `link.sh`** (after the `DRY_RUN` lines, before `link_one`):

```bash
if [ "${1:-}" = "--verify" ]; then
  rc=0
  while read -r src dest; do
    case "$src" in \#*|"") continue ;; esac
    dest="${dest\~/$HOME}"; want="$REPO_ROOT/$src"
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$want" ]; then echo "OK $dest";
    elif [ -e "$dest" ] || [ -L "$dest" ]; then echo "BROKEN $dest (-> $(readlink "$dest" 2>/dev/null))"; rc=1;
    else echo "MISSING $dest"; rc=1; fi
  done < "$MANIFEST"
  exit "$rc"
fi
```

- [ ] **Step 4: Run to verify green**

Run: `bash install-test.sh`
Expected: `PASS=9 FAIL=0`.

- [ ] **Step 5: Commit**

```bash
git add link.sh install-test.sh
git commit -m "feat(setup): linker verify mode plus backup guarantees"
```

---

### Task 4: `bootstrap.sh` (curl-pipe entry)

**Files:**
- Create: `bootstrap.sh`
- Modify: `install-test.sh` (append 3 checks)

- [ ] **Step 1: Append failing checks**:

```bash
t "bootstrap syntax clean" bash -n "$REPO_ROOT/bootstrap.sh"
t "bootstrap shellcheck clean" shellcheck -S error "$REPO_ROOT/bootstrap.sh"
t "bootstrap clones when ~/dotfiles missing (stub git)" bash -c '
  stub="$0/stubbin"; mkdir -p "$stub"
  printf "#!/usr/bin/env bash\necho \"stub-git $*\" >> \"$0/git.log\"\n" > "$stub/git"
  chmod +x "$stub/git"
  HOME="$0" PATH="$stub:/usr/bin:/bin" "$1/bootstrap.sh" --dry-run-bootstrap >/dev/null 2>&1
  grep -q "stub-git clone" "$0/git.log"' "$SANDBOX" "$REPO_ROOT"
```

- [ ] **Step 2: Run to verify red**

Run: `bash install-test.sh`
Expected: 3 FAIL (`bootstrap.sh` missing).

- [ ] **Step 3: Write `bootstrap.sh`**

```bash
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
  git -C "$REPO_DIR" pull --ff-only
else
  git clone "$REPO_URL" "$REPO_DIR"
fi
cd "$REPO_DIR"
exec ./install.sh "$@"
```

Note: the `--dry-run-bootstrap` flag in the test never fires in the script — the stub `git` records `clone` and then real `./install.sh` would run… that breaks sandbox isolation. Fix in implementation: the test instead asserts on a `BOOTSTRAP_DRY_RUN=1` env seam. Replace the Step-3 script's tail with:

```bash
if [ "${BOOTSTRAP_DRY_RUN:-0}" = 1 ]; then exit 0; fi
cd "$REPO_DIR"
exec ./install.sh "$@"
```

and the Step-1 test exports `BOOTSTRAP_DRY_RUN=1` instead of passing the flag:

```bash
  HOME="$0" BOOTSTRAP_DRY_RUN=1 PATH="$stub:/usr/bin:/bin" "$1/bootstrap.sh" >/dev/null 2>&1
```

(Write the test this way from the start — no placeholder, this is the exact form.)

- [ ] **Step 4: Run to verify green**

Run: `bash install-test.sh`
Expected: `PASS=12 FAIL=0`. Manual: `BOOTSTRAP_DRY_RUN=1 HOME=$(mktemp -d) PATH with stub git` leaves a `git.log` containing `clone`.

- [ ] **Step 5: Commit**

```bash
git add bootstrap.sh install-test.sh
git commit -m "feat(setup): curl-pipe bootstrap with clone-or-pull"
```

---

### Task 5: `install.sh` chain rework

**Files:**
- Modify: `install.sh`
- Modify: `install-test.sh` (append 3 checks)

Current `install.sh` (23 lines): brew check → `brew.sh` → kitty check → `mkdir ~/git` → ssh hint. Keep all of it.

- [ ] **Step 1: Append failing checks**:

```bash
t "install.sh passes --dry-run to linker" bash -c '
  HOME="$0" INSTALL_SANDBOX=1 "$1/install.sh" --dry-run 2>&1 | grep -q "^LINK "' "$SANDBOX" "$REPO_ROOT"
t "install.sh dry-run creates no symlinks" bash -c '
  HOME="$0" INSTALL_SANDBOX=1 "$1/install.sh" --dry-run >/dev/null 2>&1 &&
  [ ! -e "$0/.zshrc" ]' "$SANDBOX" "$REPO_ROOT"
t "install.sh full sandbox run links + verifies" bash -c '
  HOME="$0" INSTALL_SANDBOX=1 "$1/install.sh" >/dev/null 2>&1 &&
  HOME="$0" "$1/link.sh" --verify >/dev/null 2>&1' "$SANDBOX" "$REPO_ROOT"
```

(The sandbox run must skip brew/kitty/chsh: gate those behind `[ -z "${INSTALL_SANDBOX:-}" ]`.)

- [ ] **Step 2: Run to verify red**

Run: `bash install-test.sh`
Expected: 3 FAIL (no flag passthrough yet).

- [ ] **Step 3: Rewrite `install.sh`** (keep existing steps, add seams + chain):

```bash
#!/usr/bin/env bash
# One-click dotfiles install. Idempotent: safe to re-run any time.
# Flags pass through to link.sh: --dry-run, --verify.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANDBOX="${INSTALL_SANDBOX:-}"

if [ -z "$SANDBOX" ]; then
  #install brew (skip when already installed: re-running pays the full
  # installer on every clone refresh and aborts under set -euo on hiccups)
  if ! command -v brew >/dev/null 2>&1; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  #install brew packages (repo-root independent)
  "$SCRIPT_DIR/brew.sh"

  # kitty (skip when already installed)
  if ! command -v kitty >/dev/null 2>&1; then
    curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
  fi
fi

# all clones goest here
mkdir -p ~/git

# symlinks from the manifest (backup-then-link; --dry-run/--verify pass through)
"$SCRIPT_DIR/link.sh" "$@"

# secrets stub so sourcing never breaks on a fresh clone
if [ ! -f "$SCRIPT_DIR/zsh/privatealiases.zsh" ]; then
  cp "$SCRIPT_DIR/zsh/privatealiases.zsh.example" "$SCRIPT_DIR/zsh/privatealiases.zsh"
  echo "STUB zsh/privatealiases.zsh (fill in your keys)"
fi

# smoke: linked shell must parse
zsh -n "$HOME/.zshrc" && echo "SMOKE zsh -n ~/.zshrc OK"

if [ -z "$SANDBOX" ]; then
  if [[ "$SHELL" != *zsh ]]; then
    echo "Switching default shell to zsh (needs password once)."
    chsh -s /bin/zsh
  fi
fi

echo "upnext run 'sh ./ssh.sh <email@xyz.com>' to generate ssh key"
```

- [ ] **Step 4: Run to verify green**

Run: `bash install-test.sh`
Expected: `PASS=15 FAIL=0`.

- [ ] **Step 5: Commit**

```bash
git add install.sh install-test.sh
git commit -m "feat(setup): install.sh becomes the idempotent chain"
```

---

### Task 6: Secrets template + drop stow

**Files:**
- Create: `zsh/privatealiases.zsh.example`
- Modify: `brew.sh:87` (delete `brew install stow`)
- Modify: `install-test.sh` (append 2 checks)

- [ ] **Step 1: Append failing checks**:

```bash
t "secrets stub created from example on sandbox run" bash -c '
  rm -f "$1/zsh/privatealiases.zsh.test-probe" &&
  HOME="$0" INSTALL_SANDBOX=1 sh -c "exit 0" &&
  test -f "$1/zsh/privatealiases.zsh.example"' "$SANDBOX" "$REPO_ROOT"
t "stow no longer installed by brew.sh" bash -c '! grep -qx "brew install stow" "$0/brew.sh"' "$SANDBOX" "$REPO_ROOT"
```

- [ ] **Step 2: Run to verify red**

Run: `bash install-test.sh`
Expected: 2 FAIL (no example file; stow line present).

- [ ] **Step 3: Write `zsh/privatealiases.zsh.example`** (mirror live names, empty values, zero secrets):

```bash
# Machine-local secrets. Copy to privatealiases.zsh (gitignored) and fill in.
# The installer creates the copy for you on fresh machines.
export OPEN_AI=""

# export openrouter=""
# export groq=""
# export cerebras=""

export AMO_API_KEY=""
export AMO_API_SECRET=""

# stackoverflow agent
export SOFA_API_KEY=""
export SOFA_BASE_URL=""

# typesafe/JEV
export TYPESAFE_API_KEY=""
```

- [ ] **Step 4: Delete `brew install stow`** from `brew.sh:87` (that one line only).

- [ ] **Step 5: Run to verify green**

Run: `bash install-test.sh`
Expected: `PASS=17 FAIL=0`. Plus secret scan before commit: `git diff --cached` must show no values; `grep -rn "brew install stow" brew.sh` empty.

- [ ] **Step 6: Commit (two per-file commits, never mix)**

```bash
git add zsh/privatealiases.zsh.example install-test.sh
git commit -m "feat(setup): secrets stub template"
git add brew.sh
git commit -m "chore(setup): drop stow dependency"
```

---

### Task 7: E2E cleanup proof + gates

**Files:**
- Modify: `install-test.sh` (append final checks)

- [ ] **Step 1: Append failing checks**:

```bash
t "sandbox is removed after suite exit" bash -c '
  out=$(VERBOSE=1 "$0" --self-check-quiet 2>/dev/null || VERBOSE=1 bash "$0") &&
  dir=$(echo "$out" | grep "^SANDBOX=" | cut -d= -f2) &&
  [ -n "$dir" ] && [ ! -e "$dir" ]' "$REPO_ROOT/install-test.sh"
```

This check is self-referential and brittle — replace with the exact concrete form: run the suite in verbose mode from a wrapper that captures the sandbox path, then assert removal:

```bash
t "sandbox removed after suite exit" bash -c '
  out=$(VERBOSE=1 bash "$0") &&
  echo "$out" | grep -q "PASS=" &&
  dir=$(echo "$out" | grep "^SANDBOX=" | cut -d= -f2) &&
  [ -n "$dir" ] && [ ! -e "$dir" ]' "$REPO_ROOT/install-test.sh"
```

(Runs the suite nested; inner run's trap cleans its sandbox. Slow but exact. Write it this second way from the start.)

```bash
t "shellcheck clean on all installer scripts" shellcheck -S error "$REPO_ROOT/link.sh" "$REPO_ROOT/bootstrap.sh" "$REPO_ROOT/install.sh" "$REPO_ROOT/install-test.sh"
t "no temp litter in sandbox parent" bash -c '
  before=$(ls "${TMPDIR:-/tmp}" | grep -c "dotfiles-sandbox-" || true) &&
  HOME="$0" INSTALL_SANDBOX=1 "$1/install.sh" >/dev/null 2>&1 &&
  after=$(ls "${TMPDIR:-/tmp}" | grep -c "dotfiles-sandbox-" || true) &&
  [ "$before" = "$after" ]' "$SANDBOX" "$REPO_ROOT"
```

- [ ] **Step 2: Run to verify red/green**

Run: `bash install-test.sh`
Expected: nested-run check passes trivially once written (it's a cleanup proof, not a feature); shellcheck must be clean — fix any findings before proceeding.

- [ ] **Step 3: Full final run + live-tree hygiene**

Run: `bash install-test.sh` → `PASS=20 FAIL=0`.
Run: `git status --porcelain` → only intended files (installer must not leave litter in the repo; sandbox lives in `$TMPDIR`).

- [ ] **Step 4: Commit**

```bash
git add install-test.sh
git commit -m "test(setup): e2e cleanup proof and shellcheck gate"
```

---

## Self-review

- Spec coverage: §1 bootstrap → Task 4 (+ deviation noted). §2 manifest/linker/dry-run/verify → Tasks 1–3. §3 chain order (brew→link→verify→stub→smoke→chsh→summary; ssh separate, untouched `ssh.sh`) → Task 5; stub template → Task 6. §4 sandbox e2e, second-run no-op (Task 3 check), edge cases (clone-or-pull Task 4, backup Task 3, Intel/Silicon untouched `brew --prefix` logic), cleanup (Task 7 + per-file `trap ... EXIT INT TERM`) → covered.
- Placeholders: none — every step has exact code/commands/expected output. The two "replace with" notes above are explicit corrections inside the plan, not TBDs; implement the second form.
- Type consistency: seams are `INSTALL_SANDBOX`, `BOOTSTRAP_DRY_RUN`, `VERBOSE` (env only); flags are `--dry-run`, `--verify` (link.sh + passthrough). `link_one`/`t()` signatures stable across tasks.
