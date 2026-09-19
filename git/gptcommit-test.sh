#!/usr/bin/env bash
# Regression test for git/gptcommit.sh.
# Exercises the GENERATION path (SOURCE empty/"message") — the old version
# passed `commit` as $2, which only ever tested the skip path at :100.
#
# Seams (no network, no TTY, no waiting):
#   stub curl on PATH  → canned OpenAI payload, "200", no network
#   GPTCOMMIT_NO_SLEEP → skip retry backoff
#   GPTCOMMIT_TTY      → /dev/null answers EOF, which keeps the draft
set -uo pipefail

fail=0
check() { # check <desc> <want> <got>
  if [[ "$2" == "$3" ]]; then
    echo "ok - $1"
  else
    echo "NOT OK - $1 (want [$2] got [$3])"
    fail=1
  fi
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GPTCOMMIT="$REPO_ROOT/git/gptcommit.sh"

# ── unit: ticket_from_branch (pure — no repo needed) ─────────────────────────
# shellcheck disable=SC1091
. "$REPO_ROOT/git/lib/ticket.sh"
check "ticket from feature branch" "ABC-123" "$(ticket_from_branch 'feature/ABC-123-thing')"
check "first key wins" "XY-9" "$(ticket_from_branch 'hotfix/XY-9-and-ZZ-10')"
check "no key on main" "" "$(ticket_from_branch 'main')"
check "single-letter prefix is not a key" "" "$(ticket_from_branch 'a/A-1-x')"
check "lowercase is not a key" "" "$(ticket_from_branch 'feature/abc-123')"
check "empty branch name" "" "$(ticket_from_branch '')"
ticket_from_branch 'main' >/dev/null
check "exit 0 on empty (set -e safe)" "0" "$?"

# ── end-to-end: generation path with stubbed transport ───────────────────────
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT INT TERM
mkdir -p "$FIXTURE/bin" "$FIXTURE/repo"
cat > "$FIXTURE/bin/curl" <<'EOF'
#!/bin/sh
# stub: OpenAI-shaped payload into the -o file, "200" on stdout
out=""; prev=""
for a in "$@"; do
  if [ "$prev" = "-o" ]; then out="$a"; fi
  prev="$a"
done
[ -n "$out" ] || exit 1
printf '{"choices":[{"message":{"content":"feat(TEST-123): stubbed commit"}}]}' > "$out"
printf '200'
EOF
chmod +x "$FIXTURE/bin/curl"

git -C "$FIXTURE/repo" init -q -b TEST-123-demo 2>/dev/null \
  || git -C "$FIXTURE/repo" init -q
git -C "$FIXTURE/repo" checkout -q -B TEST-123-demo
git -C "$FIXTURE/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
echo change > "$FIXTURE/repo/file.txt"
git -C "$FIXTURE/repo" add file.txt

MSG="$FIXTURE/msg"
(
  cd "$FIXTURE/repo" &&
  PATH="$FIXTURE/bin:$PATH" OPENAI_API_KEY=test \
    GPTCOMMIT_NO_SLEEP=1 GPTCOMMIT_TTY=/dev/null \
    bash "$GPTCOMMIT" "$MSG" message
)
check "hook exit 0" "0" "$?"
check "draft written to message file" "feat(TEST-123): stubbed commit" "$(cat "$MSG")"

# ── fallback path: deletion-only diff takes the first fallback ──────────────
git -C "$FIXTURE/repo" -c user.email=t@t -c user.name=t commit -q -m add file.txt
git -C "$FIXTURE/repo" rm -q file.txt
MSG_DEL="$FIXTURE/msg-del"
(
  cd "$FIXTURE/repo" &&
  PATH="$FIXTURE/bin:$PATH" OPENAI_API_KEY=test \
    GPTCOMMIT_NO_SLEEP=1 GPTCOMMIT_TTY=/dev/null \
    bash "$GPTCOMMIT" "$MSG_DEL" message
)
check "fallback exit 0" "0" "$?"
if [[ -s "$MSG_DEL" ]]; then echo "ok - fallback writes a message"; else echo "NOT OK - fallback writes a message (empty file)"; fail=1; fi

# ── skip path: SOURCE=commit leaves the file alone ──────────────────────────
echo "untouched" > "$FIXTURE/skipmsg"
(
  cd "$FIXTURE/repo" &&
  bash "$GPTCOMMIT" "$FIXTURE/skipmsg" commit
)
check "skip-path exit 0" "0" "$?"
check "skip-path leaves file alone" "untouched" "$(cat "$FIXTURE/skipmsg")"

# ── degraded path: missing lib still runs help with a warning ──────────────
mkdir "$FIXTURE/nolib"
cp "$GPTCOMMIT" "$FIXTURE/nolib/solo.sh"
(cd "$FIXTURE/nolib" && bash solo.sh help >"$FIXTURE/helpout" 2>&1)
check "missing-lib help exit 0" "0" "$?"
if grep -q "ticket library missing" "$FIXTURE/helpout"; then echo "ok - missing-lib warns"; else echo "NOT OK - missing-lib warns"; fail=1; fi

# ── degraded path: missing lib still generates (no ticket, warning) ─────────
echo more > "$FIXTURE/repo/other.txt"
git -C "$FIXTURE/repo" add other.txt
MSG_NOLIB="$FIXTURE/nolib-msg"
(
  cd "$FIXTURE/repo" &&
  PATH="$FIXTURE/bin:$PATH" OPENAI_API_KEY=test \
    GPTCOMMIT_NO_SLEEP=1 GPTCOMMIT_TTY=/dev/null \
    bash "$FIXTURE/nolib/solo.sh" "$MSG_NOLIB" message 2>"$FIXTURE/nolib-err"
)
check "missing-lib generation exit 0" "0" "$?"
check "missing-lib writes draft" "feat(TEST-123): stubbed commit" "$(cat "$MSG_NOLIB")"
if grep -q "ticket library missing" "$FIXTURE/nolib-err"; then echo "ok - missing-lib generation warns"; else echo "NOT OK - missing-lib generation warns"; fail=1; fi

if (( fail )); then echo "FAIL"; else echo "PASS"; fi
exit "$fail"
