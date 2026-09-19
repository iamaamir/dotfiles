#!/usr/bin/env bash
# Sandbox suite for the one-click installer. Never touches the live $HOME.
# Tests that mutate repo-side files (stub, src-hide) always guard with a
# trap restore, so INT/TERM can never lose data.
# shellcheck disable=SC2016 # $0/$1 inside single-quoted bash -c bodies expand in the INNER shell by design.
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
  d="$0/fresh"; mkdir -p "$d" &&
  HOME="$d" "$1/link.sh" >/dev/null 2>&1 &&
  [ -L "$d/.zshrc" ] && [ "$(readlink "$d/.zshrc")" = "$1/zsh/.zshrc" ]' "$SANDBOX" "$REPO_ROOT"
t "all 6 manifest dests resolve" bash -c '
  d="$0/all6"; mkdir -p "$d" &&
  HOME="$d" "$1/link.sh" >/dev/null 2>&1 &&
  while read -r src dest || [[ -n "$src" ]]; do case "$src" in \#*|"") continue;; esac
    dest="${dest/#\~/$d}"
    [ -e "$dest" ] || exit 1
  done < "$1/links.txt"' "$SANDBOX" "$REPO_ROOT"
t "clash is backed up, not overwritten" bash -c '
  d="$0/clash"; mkdir -p "$d" &&
  echo original > "$d/.zshrc" &&
  HOME="$d" "$1/link.sh" >/dev/null 2>&1 &&
  [ -L "$d/.zshrc" ] &&
  grep -rq original "$d/.dotfiles-backup/"' "$SANDBOX" "$REPO_ROOT"
t "backup preserves directory structure" bash -c '
  d="$0/struct"; mkdir -p "$d/.config" &&
  echo orig > "$d/.config/starship.toml" &&
  HOME="$d" "$1/link.sh" >/dev/null 2>&1 &&
  [ -f "$d"/.dotfiles-backup/*/".config/starship.toml" ] &&
  grep -q orig "$d"/.dotfiles-backup/*/".config/starship.toml"' "$SANDBOX" "$REPO_ROOT"
t "link refuses missing src" bash -c '
  src="$1/zsh/.zshrc"
  restore() { mv "$src.hide" "$src"; }; trap restore EXIT INT TERM
  d="$0/nosrc"; mkdir -p "$d" &&
  mv "$src" "$src.hide" &&
  out=$(HOME="$d" "$1/link.sh" 2>&1); rc=$?
  [ "$rc" -ne 0 ] && printf "%s" "$out" | grep -q "SRC-MISSING" &&
  [ ! -e "$d/.zshrc" ]' "$SANDBOX" "$REPO_ROOT"
t "mid-manifest missing src aborts, earlier links stand" bash -c '
  src="$1/.config/starship.toml"
  restore() { mv "$src.hide" "$src"; }; trap restore EXIT INT TERM
  d="$0/midsrc"; mkdir -p "$d" &&
  mv "$src" "$src.hide" &&
  out=$(HOME="$d" "$1/link.sh" 2>&1); rc=$?
  [ "$rc" -ne 0 ] && printf "%s" "$out" | grep -q "SRC-MISSING" &&
  [ -L "$d/.zshrc" ] && [ ! -e "$d/.config/starship.toml" ]' "$SANDBOX" "$REPO_ROOT"
t "link rejects extra manifest field" bash -c '
  printf "zsh/.zshrc ~/.zshrc extra-field\n" > "$0/extra-manifest" &&
  out=$(LINKS_MANIFEST="$0/extra-manifest" HOME="$0" "$1/link.sh" 2>&1); rc=$?
  rm -f "$0/extra-manifest"
  [ "$rc" -ne 0 ] && printf "%s" "$out" | grep -q "MANIFEST-BAD"' "$SANDBOX" "$REPO_ROOT"
t "link rejects directory manifest" bash -c '
  mkdir -p "$0/manifestdir" &&
  out=$(LINKS_MANIFEST="$0/manifestdir" HOME="$0" "$1/link.sh" 2>&1); rc=$?
  rmdir "$0/manifestdir"
  [ "$rc" -ne 0 ] && printf "%s" "$out" | grep -q "MANIFEST-MISSING"' "$SANDBOX" "$REPO_ROOT"
t "link rejects tilde-user dest" bash -c '
  printf "zsh/.zshrc ~otheruser/.zshrc\n" > "$0/usermanifest" &&
  out=$(LINKS_MANIFEST="$0/usermanifest" HOME="$0/h4" "$1/link.sh" 2>&1); rc=$?
  rm -f "$0/usermanifest"
  [ "$rc" -ne 0 ] && printf "%s" "$out" | grep -q "REFUSE"' "$SANDBOX" "$REPO_ROOT"
t "link refuses dest outside HOME" bash -c '
  printf "zsh/.zshrc /tmp/install-test-evil-target\n" > "$0/evil-manifest" &&
  out=$(LINKS_MANIFEST="$0/evil-manifest" HOME="$0" "$1/link.sh" 2>&1); rc=$?
  rm -f "$0/evil-manifest"
  [ "$rc" -ne 0 ] && printf "%s" "$out" | grep -q "REFUSE" &&
  [ ! -e /tmp/install-test-evil-target ]' "$SANDBOX" "$REPO_ROOT"
t "link rejects unknown flag" bash -c '
  out=$("$1/link.sh" --bogus 2>&1); rc=$?
  [ "$rc" -eq 2 ] && printf "%s" "$out" | grep -q "usage"' "$SANDBOX" "$REPO_ROOT"
t "link rejects extra args" bash -c '
  d="$0/extra"; mkdir -p "$d"
  out=$(HOME="$d" "$1/link.sh" --dry-run --verify 2>&1); rc=$?
  [ "$rc" -eq 2 ] && printf "%s" "$out" | grep -q "usage" &&
  [ ! -e "$d/.zshrc" ]' "$SANDBOX" "$REPO_ROOT"
t "link rejects .. escape" bash -c '
  printf "zsh/.zshrc ~/.x/../../suite-escape\n" > "$0/escape-manifest" &&
  out=$(LINKS_MANIFEST="$0/escape-manifest" HOME="$0/h" "$1/link.sh" 2>&1); rc=$?
  rm -f "$0/escape-manifest"
  [ "$rc" -ne 0 ] && printf "%s" "$out" | grep -q "REFUSE" &&
  [ ! -e "$0/suite-escape" ]' "$SANDBOX" "$REPO_ROOT"
t "link refuses HOME itself as dest" bash -c '
  printf "zsh/.zshrc ~/\n" > "$0/homemanifest" &&
  out=$(LINKS_MANIFEST="$0/homemanifest" HOME="$0" "$1/link.sh" 2>&1); rc=$?
  rm -f "$0/homemanifest"
  [ "$rc" -ne 0 ] && printf "%s" "$out" | grep -q "REFUSE"' "$SANDBOX" "$REPO_ROOT"
t "link fails cleanly on missing manifest" bash -c '
  out=$(LINKS_MANIFEST="$0/does-not-exist" HOME="$0" "$1/link.sh" 2>&1); rc=$?
  [ "$rc" -ne 0 ] && printf "%s" "$out" | grep -q "MANIFEST-MISSING"' "$SANDBOX" "$REPO_ROOT"
t "link reads unterminated last line" bash -c '
  d="$0/unterm"; mkdir -p "$d" &&
  printf "zsh/.zshrc ~/.zshrc\nzsh/.zshenv ~/.zshenv" > "$d/mm" &&
  HOME="$d" LINKS_MANIFEST="$d/mm" "$1/link.sh" >/dev/null 2>&1 &&
  [ -L "$d/.zshrc" ] && [ -L "$d/.zshenv" ]' "$SANDBOX" "$REPO_ROOT"
t "second run is a no-op (all SKIP)" bash -c '
  d="$0/noop"; mkdir -p "$d" &&
  HOME="$d" "$1/link.sh" >/dev/null 2>&1 &&
  [ -z "$(HOME="$d" "$1/link.sh" 2>&1 | grep -v "^SKIP ")" ]' "$SANDBOX" "$REPO_ROOT"
t "dry-run changes nothing on disk" bash -c '
  d="$0/dry"; mkdir -p "$d"
  HOME="$d" "$1/link.sh" --dry-run >/dev/null 2>&1
  [ ! -e "$d/.zshrc" ] && [ ! -L "$d/.zshrc" ] && [ ! -d "$d/.dotfiles-backup" ]' "$SANDBOX" "$REPO_ROOT"
t "verify reports all OK" bash -c '
  set -o pipefail
  d="$0/verify"; mkdir -p "$d" &&
  HOME="$d" "$1/link.sh" >/dev/null 2>&1 &&
  out=$(HOME="$d" "$1/link.sh" --verify 2>&1) &&
  [ "$(printf "%s" "$out" | grep -c "^OK ")" -eq 6 ] &&
  ! printf "%s" "$out" | grep -qE "^(BROKEN|MISSING) "' "$SANDBOX" "$REPO_ROOT"
t "verify flags tampered dest as BROKEN" bash -c '
  d="$0/broken"; mkdir -p "$d" &&
  HOME="$d" "$1/link.sh" >/dev/null 2>&1 &&
  rm "$d/.zshrc" && echo tampered > "$d/.zshrc"
  out=$(HOME="$d" "$1/link.sh" --verify 2>&1); rc=$?
  [ "$rc" -ne 0 ] && printf "%s" "$out" | grep -q "^BROKEN "' "$SANDBOX" "$REPO_ROOT"
t "verify flags dangling target as BROKEN" bash -c '
  src="$1/zsh/.zshrc"
  restore() { mv "$src.hide" "$src"; }; trap restore EXIT INT TERM
  d="$0/dangle"; mkdir -p "$d" &&
  HOME="$d" "$1/link.sh" >/dev/null 2>&1 &&
  mv "$src" "$src.hide"
  out=$(HOME="$d" "$1/link.sh" --verify 2>&1); rc=$?
  [ "$rc" -ne 0 ] && printf "%s" "$out" | grep -q "^BROKEN "' "$SANDBOX" "$REPO_ROOT"
t "bootstrap syntax clean" bash -n "$REPO_ROOT/bootstrap.sh"
t "bootstrap shellcheck clean" shellcheck -S error "$REPO_ROOT/bootstrap.sh"
t "bootstrap clones when ~/dotfiles missing (stub git)" bash -c '
  stub="$0/stubbin"; mkdir -p "$stub"
  rm -f "$0/git.log"
  printf "#!/usr/bin/env bash\necho \"stub-git \$*\" >> \"$0/git.log\"\n" > "$stub/git"
  chmod +x "$stub/git"
  HOME="$0" BOOTSTRAP_DRY_RUN=1 PATH="$stub:/usr/bin:/bin" "$1/bootstrap.sh" >/dev/null 2>&1
  grep -q "stub-git clone --recurse-submodules" "$0/git.log"' "$SANDBOX" "$REPO_ROOT"
t "bootstrap pulls and updates submodules when checkout exists" bash -c '
  stub="$0/stubbin2"; mkdir -p "$stub" "$0/dots/dotfiles/.git"
  rm -f "$0/git2.log"
  printf "#!/usr/bin/env bash\necho \"stub-git \$*\" >> \"$0/git2.log\"\n" > "$stub/git"
  chmod +x "$stub/git"
  HOME="$0/dots" BOOTSTRAP_DRY_RUN=1 PATH="$stub:/usr/bin:/bin" "$1/bootstrap.sh" >/dev/null 2>&1
  grep -q "stub-git -C .* pull --ff-only" "$0/git2.log" &&
  grep -q "stub-git -C .* submodule update --init --recursive" "$0/git2.log"' "$SANDBOX" "$REPO_ROOT"
t "bootstrap refuses non-checkout dir" bash -c '
  stub="$0/stubbin3"; mkdir -p "$stub"
  printf "#!/usr/bin/env bash\necho stub-git >> \"$0/git3.log\"\n" > "$stub/git"
  chmod +x "$stub/git"
  d="$0/dots3"; mkdir -p "$d"; echo junk > "$d/dotfiles"
  out=$(HOME="$d" PATH="$stub:/usr/bin:/bin" "$1/bootstrap.sh" 2>&1); rc=$?
  [ "$rc" -ne 0 ] && printf "%s" "$out" | grep -q "move it aside"' "$SANDBOX" "$REPO_ROOT"
t "bootstrap rejects dual flags before git work" bash -c '
  stub="$0/stubbin5"; mkdir -p "$stub"
  rm -f "$0/git5.log"
  printf "#!/usr/bin/env bash\necho \"stub-git \$*\" >> \"$0/git5.log\"\n" > "$stub/git"
  chmod +x "$stub/git"
  out=$(HOME="$0" PATH="$stub:/usr/bin:/bin" "$1/bootstrap.sh" --dry-run --verify 2>&1); rc=$?
  [ "$rc" -eq 2 ] && printf "%s" "$out" | grep -q "usage" &&
  { [ ! -e "$0/git5.log" ] || ! grep -q "stub-git" "$0/git5.log"; }' "$SANDBOX" "$REPO_ROOT"
t "bootstrap --help exits before git" bash -c '
  stub="$0/stubbin4"; mkdir -p "$stub"
  printf "#!/usr/bin/env bash\necho stub-git >> \"$0/git4.log\"\n" > "$stub/git"
  chmod +x "$stub/git"
  rm -f "$0/git4.log"
  out=$(HOME="$0" PATH="$stub:/usr/bin:/bin" "$1/bootstrap.sh" --help 2>&1); rc=$?
  [ "$rc" -eq 0 ] && printf "%s" "$out" | grep -q "usage" &&
  { [ ! -e "$0/git4.log" ] || ! grep -q "stub-git" "$0/git4.log"; }' "$SANDBOX" "$REPO_ROOT"
t "install.sh passes --dry-run to linker" bash -c '
  d="$0/idrypass"; mkdir -p "$d"
  out=$(HOME="$d" INSTALL_SANDBOX=1 "$1/install.sh" --dry-run 2>&1); rc=$?
  [ "$rc" -eq 0 ] && grep -q "^LINK " <<<"$out"' "$SANDBOX" "$REPO_ROOT"
t "install.sh dry-run plans all 6 entries" bash -c '
  d="$0/idrycount"; mkdir -p "$d"
  out=$(HOME="$d" INSTALL_SANDBOX=1 "$1/install.sh" --dry-run 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [ "$(grep -c "^LINK " <<<"$out")" -eq 6 ]' "$SANDBOX" "$REPO_ROOT"
t "install.sh rejects extra args" bash -c '
  d="$0/iextra"; mkdir -p "$d"
  out=$(HOME="$d" INSTALL_SANDBOX=1 "$1/install.sh" --dry-run extra 2>&1); rc=$?
  [ "$rc" -eq 2 ] && printf "%s" "$out" | grep -q "usage" &&
  [ ! -e "$d/.zshrc" ]' "$SANDBOX" "$REPO_ROOT"
t "install.sh --help exits clean" bash -c '
  out=$(HOME="$0" INSTALL_SANDBOX=1 "$1/install.sh" --help 2>&1); rc=$?
  [ "$rc" -eq 0 ] && printf "%s" "$out" | grep -q "usage"' "$SANDBOX" "$REPO_ROOT"
t "install.sh dry-run creates no symlinks, dirs, or stubs" bash -c '
  p="$1/zsh/privatealiases.zsh"; had=0
  restore() { rm -f "$p"; if [ "$had" = 1 ]; then mv "$p.testsave" "$p"; fi; }
  trap restore EXIT INT TERM
  if [ -f "$p" ]; then had=1; mv "$p" "$p.testsave"; fi
  d="$0/idry"; mkdir -p "$d"
  HOME="$d" INSTALL_SANDBOX=1 "$1/install.sh" --dry-run >/dev/null 2>&1
  [ ! -e "$d/.zshrc" ] && [ ! -L "$d/.zshrc" ] && [ ! -e "$d/git" ] && [ ! -f "$p" ]' "$SANDBOX" "$REPO_ROOT"
t "install.sh full sandbox run links, verifies, smokes" bash -c '
  set -o pipefail
  d="$0/ifull"; mkdir -p "$d"; ln -sfn "$1" "$d/dotfiles" &&
  out=$(HOME="$d" INSTALL_SANDBOX=1 "$1/install.sh" 2>&1); rc=$?
  [ "$rc" -eq 0 ] &&
  printf "%s" "$out" | grep -q "^OK " &&
  printf "%s" "$out" | grep -q "SMOKE.*sources silently OK" &&
  printf "%s" "$out" | grep -q "^DONE: 6 links OK" &&
  HOME="$d" "$1/link.sh" --verify >/dev/null 2>&1' "$SANDBOX" "$REPO_ROOT"
t "link abort leaves no ~/git behind" bash -c '
  src="$1/.config/starship.toml"
  restore() { mv "$src.hide" "$src"; }; trap restore EXIT INT TERM
  d="$0/nogit"; mkdir -p "$d"; ln -sfn "$1" "$d/dotfiles" &&
  mv "$src" "$src.hide" &&
  out=$(HOME="$d" INSTALL_SANDBOX=1 "$1/install.sh" 2>&1); rc=$?
  [ "$rc" -ne 0 ] && [ ! -e "$d/git" ]' "$SANDBOX" "$REPO_ROOT"
t "linked nvim tree is non-empty" bash -c '
  d="$0/invim"; mkdir -p "$d"; ln -sfn "$1" "$d/dotfiles" &&
  HOME="$d" INSTALL_SANDBOX=1 "$1/install.sh" >/dev/null 2>&1 &&
  [ -n "$(ls -A "$d/.config/nvim")" ]' "$SANDBOX" "$REPO_ROOT"
t "empty backup dir does not fail install" bash -c '
  d="$0/ibackup"; mkdir -p "$d/.dotfiles-backup"; ln -sfn "$1" "$d/dotfiles" &&
  out=$(HOME="$d" INSTALL_SANDBOX=1 "$1/install.sh" 2>&1); rc=$?
  [ "$rc" -eq 0 ] && printf "%s" "$out" | grep -q "^DONE:"' "$SANDBOX" "$REPO_ROOT"
t "one run uses a single backup dir" bash -c '
  d="$0/ionestamp"; mkdir -p "$d/.config" &&
  echo a > "$d/.zshrc" && echo b > "$d/.config/starship.toml" &&
  HOME="$d" "$1/link.sh" >/dev/null 2>&1 &&
  [ "$(find "$d/.dotfiles-backup" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ]' "$SANDBOX" "$REPO_ROOT"
t "install.sh verify-only checks without mutating" bash -c '
  p="$1/zsh/privatealiases.zsh"; had=0
  restore() { rm -f "$p"; if [ "$had" = 1 ]; then mv "$p.testsave" "$p"; fi; }
  trap restore EXIT INT TERM
  if [ -f "$p" ]; then had=1; mv "$p" "$p.testsave"; fi
  d="$0/iverify"; mkdir -p "$d"
  out=$(HOME="$d" INSTALL_SANDBOX=1 "$1/install.sh" --verify 2>&1); rc=$?
  [ "$rc" -ne 0 ] &&
  printf "%s" "$out" | grep -q "^MISSING " &&
  [ ! -e "$d/git" ] && [ ! -e "$d/.zshrc" ] && [ ! -f "$p" ]' "$SANDBOX" "$REPO_ROOT"
t "verify-only reports missing stub honestly" bash -c '
  p="$1/zsh/privatealiases.zsh"; had=0
  restore() { rm -f "$p"; if [ "$had" = 1 ]; then mv "$p.testsave" "$p"; fi; }
  trap restore EXIT INT TERM
  if [ -f "$p" ]; then had=1; mv "$p" "$p.testsave"; fi
  d="$0/iverifystub"; mkdir -p "$d"; ln -sfn "$1" "$d/dotfiles" &&
  HOME="$d" "$1/link.sh" >/dev/null 2>&1 &&
  out=$(HOME="$d" INSTALL_SANDBOX=1 "$1/install.sh" --verify 2>&1); rc=$?
  [ "$rc" -eq 0 ] &&
  printf "%s" "$out" | grep -q "secrets stub: missing (--verify"' "$SANDBOX" "$REPO_ROOT"
t "install.sh rejects unknown flag" bash -c '
  d="$0/ibogus"; mkdir -p "$d"
  out=$(HOME="$d" INSTALL_SANDBOX=1 "$1/install.sh" --bogus 2>&1); rc=$?
  [ "$rc" -eq 2 ] && printf "%s" "$out" | grep -q "usage" &&
  [ ! -e "$d/.zshrc" ] && [ ! -e "$d/git" ]' "$SANDBOX" "$REPO_ROOT"
t "install.sh verify-only exit code is pure verify" bash -c '
  src="$1/zsh/.zshrc"
  restore() { mv "$src.noisy" "$src"; }; trap restore EXIT INT TERM
  d="$0/iverifyrc"; mkdir -p "$d"; ln -sfn "$1" "$d/dotfiles" &&
  HOME="$d" INSTALL_SANDBOX=1 "$1/install.sh" >/dev/null 2>&1 &&
  cp "$src" "$src.noisy" && echo "echo SMOKE-PROBE-NOISE" >> "$src"
  out=$(HOME="$d" INSTALL_SANDBOX=1 "$1/install.sh" --verify 2>&1); rc=$?
  [ "$rc" -eq 0 ] && printf "%s" "$out" | grep -q "^OK "' "$SANDBOX" "$REPO_ROOT"
t "install.sh smoke fails on noisy sourcing" bash -c '
  src="$1/zsh/.zshrc"
  restore() { mv "$src.noisy" "$src"; }; trap restore EXIT INT TERM
  d="$0/inoise"; mkdir -p "$d"; ln -sfn "$1" "$d/dotfiles" &&
  cp "$src" "$src.noisy" && echo "echo SMOKE-PROBE-NOISE" >> "$src" &&
  out=$(HOME="$d" INSTALL_SANDBOX=1 "$1/install.sh" 2>&1); rc=$?
  [ "$rc" -ne 0 ] && printf "%s" "$out" | grep -q "SMOKE FAIL" &&
  printf "%s" "$out" | grep -q "SMOKE-PROBE-NOISE"' "$SANDBOX" "$REPO_ROOT"
t "stub recreated from example when missing" bash -c '
  p="$1/zsh/privatealiases.zsh"; rc=0; had=0
  restore() { rm -f "$p"; if [ "$had" = 1 ]; then mv "$p.testsave" "$p"; fi; }
  trap restore EXIT INT TERM
  if [ -f "$p" ]; then had=1; mv "$p" "$p.testsave"; fi
  d="$0/istub"; mkdir -p "$d"; ln -sfn "$1" "$d/dotfiles"
  HOME="$d" INSTALL_SANDBOX=1 "$1/install.sh" >/dev/null 2>&1 || rc=1
  cmp -s "$p" "$1/zsh/privatealiases.zsh.example" || rc=1
  exit "$rc"' "$SANDBOX" "$REPO_ROOT"
t "stow no longer installed by brew.sh" bash -c '! grep -qx "brew install stow" "$1/brew.sh"' "$SANDBOX" "$REPO_ROOT"
# Self-nesting guard: the check below re-runs this suite once to prove the
# sandbox is removed on exit; the inner run must not re-nest (see above).
if [ "${INSTALL_TEST_NESTED:-0}" != 1 ]; then
t "sandbox removed after suite exit" bash -c '
  out=$(INSTALL_TEST_NESTED=1 VERBOSE=1 bash "$0") &&
  echo "$out" | grep -q "PASS=" &&
  dir=$(echo "$out" | grep "^SANDBOX=" | cut -d= -f2) &&
  [ -n "$dir" ] && [ ! -e "$dir" ]' "$REPO_ROOT/install-test.sh"
t "shellcheck clean on all installer scripts" shellcheck "$REPO_ROOT/link.sh" "$REPO_ROOT/bootstrap.sh" "$REPO_ROOT/install.sh" "$REPO_ROOT/install-test.sh"
t "no temp litter in sandbox parent" bash -c '
  before=$(ls "${TMPDIR:-/tmp}" | grep -c "dotfiles-sandbox-" || true) &&
  d="$0/ilitter"; mkdir -p "$d"; ln -sfn "$1" "$d/dotfiles" &&
  HOME="$d" INSTALL_SANDBOX=1 "$1/install.sh" >/dev/null 2>&1 &&
  after=$(ls "${TMPDIR:-/tmp}" | grep -c "dotfiles-sandbox-" || true) &&
  [ "$before" = "$after" ]' "$SANDBOX" "$REPO_ROOT"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
