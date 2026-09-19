#!/usr/bin/env bash
set -euo pipefail
# Uncomment for very verbose tracing:
# set -x

# ── Configuration ───────────────────────────────────────────────────────────
DEBUG=${GPTCOMMIT_DEBUG:-false}

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Absolute path to this script (used by the hook stub)
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ── Logging helpers ─────────────────────────────────────────────────────────
debug() {
  # guarantee zero exit even if DEBUG=false
  if [[ "$DEBUG" == "true" ]]; then
    echo -e "${YELLOW}🐛 [DEBUG] $*${NC}" >&2
  fi
}
info()  { echo -e "${GREEN}✨ $*${NC}" >&2; }
warn()  { echo -e "${RED}⚠️  $*${NC}" >&2; }

# ── Usage / Help ────────────────────────────────────────────────────────────
print_help() {
  cat <<EOF
Usage: $(basename "$SCRIPT_PATH") [COMMAND]

Commands:
  help      Show this help message
  install   Install stub into .git/hooks/prepare-commit-msg

With no COMMAND, runs the AI-powered prepare-commit-msg hook as before.
EOF
}

# ── INSTALL: write a 4-line stub into prepare-commit-msg ────────────────────
install_hook() {
  # locate .git directory (absolute)
  raw=$(git rev-parse --git-dir 2>/dev/null) || {
    warn "Not inside a Git repository."
    exit 1
  }
  [[ "$raw" = /* ]] && GIT_DIR="$raw" || GIT_DIR="$PWD/$raw"
  HOOK="$GIT_DIR/hooks/prepare-commit-msg"

  # if already our stub, skip
  if [ -f "$HOOK" ] && grep -qxF "exec \"$SCRIPT_PATH\" \"\\\$@\"" "$HOOK"; then
    info "prepare-commit-msg hook already installed. Skipping."
    exit 0
  fi

  # if another hook exists, back it up or bail
  if [ -e "$HOOK" ]; then
    warn "Existing prepare-commit-msg hook found at $HOOK"
    cat <<EOF >&2
To install gptcommit.sh:
  1) Back up the old hook:
       mv "$HOOK" "${HOOK}.backup"
  2) Re-run:
       ./"$(basename "$SCRIPT_PATH")" install

Or merge manually, then:
  ln -sf "$SCRIPT_PATH" "$HOOK"
  chmod +x "$HOOK"
EOF
    exit 0
  fi

  # write our 4-line stub
  cat > "$HOOK" <<EOF
#!/usr/bin/env sh
# stub to invoke gptcommit.sh
exec "$SCRIPT_PATH" "\$@"
EOF
  chmod +x "$HOOK"
  info "Installed prepare-commit-msg hook → $HOOK"
  exit 0
}

# ── Dispatch install/help ────────────────────────────────────────────────────
case "${1-}" in
  install) install_hook    ;;
  help|-h) print_help; exit 0 ;;
esac

# ── HOOK ENTRYPOINT: prepare-commit-msg ──────────────────────────────────────
MSG_FILE=${1:?hook error: missing commit message file}
SOURCE=${2:-}

info "🏃‍♂️  gptcommit hook running…"
debug "MSG_FILE=$MSG_FILE"
debug "SOURCE=$SOURCE"

# ── Only run on fresh commits (SOURCE empty or "message") ────────────────────
if [[ -n "$SOURCE" && "$SOURCE" != "message" ]]; then
  debug "Skipping AI hook for source='$SOURCE'"
  exit 0
fi

# ── Skip during an interactive rebase ───────────────────────────────────────
git_dir=$(git rev-parse --git-dir)
if [[ -d "$git_dir/rebase-merge" || -d "$git_dir/rebase-apply" ]]; then
  info "Skipping AI hook during rebase"
  exit 0
fi

info "🛠️   Starting AI-powered commit message generation..."

# ── Dependency check ────────────────────────────────────────────────────────
info "🔍  Checking dependencies (git, curl, jq)…"
for cmd in git curl jq; do
  if ! command -v "$cmd" &>/dev/null; then
    warn "Missing dependency: $cmd; aborting."
    exit 1
  fi
done
info "✅  Dependencies OK"

# ── OpenAI key check ────────────────────────────────────────────────────────
info "🔑  Verifying OpenAI API key…"
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  warn "OPENAI_API_KEY not set; skipping AI commit message."
  exit 0
fi
info "✅  API key found"

# ── Gather staged files & diff ──────────────────────────────────────────────
STAGED_FILES=$(git diff --cached --name-only)
# Robust count via NUL-separated output (filenames with newlines miscounted by grep -c)
STAGED_COUNT=$(git diff --cached --name-only -z | tr -cd '\000' | wc -c | tr -d ' ')
info "📂  Found $STAGED_COUNT staged file(s)"
if (( STAGED_COUNT == 0 )); then
  warn "No staged changes; skipping AI hook."
  exit 0
fi
debug "Staged files:\n$STAGED_FILES"

DIFF=$(git diff --cached --unified=5)
debug "Diff (truncated):\n${DIFF:0:200}…"

# ── Enhanced Fallback if no additions ───────────────────────────────────────
if ! grep -q '^+[^+]' <<<"$DIFF"; then
  # build deletion & rename options (portable: no mapfile — macOS bash is 3.2)
  FALLBACKS=()
  while IFS= read -r line; do
    FALLBACKS+=("$line")
  done < <(
    # deletions
    grep '^-[^-]' <<<"$DIFF" | sed 's/^-//' | awk -F/ '{print "fix: remove "$NF}' \
    && {
      old=$(grep '^rename from ' <<<"$DIFF" | head -1 | cut -d' ' -f3)
      new=$(grep '^rename to '   <<<"$DIFF" | head -1 | cut -d' ' -f3)
      [[ -n $old && -n $new ]] && echo "refactor: rename ${old##*/} → ${new##*/}" ;
    }
  )

  if ((${#FALLBACKS[@]})); then
    if [ ! -t 0 ]; then
      # Non-interactive (hook without TTY): never block on select; take first.
      COMMIT_MSG="${FALLBACKS[0]}"
    else
      echo "🎯 No additions detected. Choose a fallback:" >&2
      select opt in "${FALLBACKS[@]}" "Custom message"; do
        if [[ $opt == "Custom message" ]]; then
          read -rp "Enter custom commit message: " COMMIT_MSG
        else
          COMMIT_MSG="$opt"
        fi
        break
      done
    fi
  else
    FIRST=$(head -n1 <<<"$STAGED_FILES")
    COMMIT_MSG="feat: add $(basename "$FIRST")"
  fi

  printf '%s\n' "$COMMIT_MSG" > "$MSG_FILE"
  exit 0
fi

# ── Branch & ticket inference ───────────────────────────────────────────────
# Canonical ticket rule for this repo: [A-Z]{2,}-[0-9]+ (shared with the
# legacy prepare-commit-msg hook; keep both in sync, prefer this file).
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ $BRANCH =~ ([A-Z]{2,}-[0-9]+) ]]; then
  TICKET=${BASH_REMATCH[1]}
  info "🔖  Detected ticket: $TICKET"
else
  TICKET=""
  info "🔖  No ticket ID found"
fi

# ── Scope inference (top-level dir of first staged path; empty at root) ────
IFS=$'\n' read -rd '' -a FILE_ARR <<<"$STAGED_FILES" || true
if (( ${#FILE_ARR[@]} )); then
  if [[ "${FILE_ARR[0]}" == */* ]]; then
    SCOPE=$(cut -d/ -f1 <<<"${FILE_ARR[0]}")
  else
    SCOPE=""
  fi
  info "💡  Inferred scope: $SCOPE"
else
  SCOPE=""
  info "💡  No scope inferred"
fi

# ── System prompt (enhanced) ────────────────────────────────────────────────
SYSTEM_PROMPT="You are an expert assistant that generates robust, accurate git commit messages following the Conventional Commits specification, including optional emojis for clarity. Format: type(scope?): subject. Subject must be ≤50 characters and in imperative mood."
[[ -n $TICKET ]] && SYSTEM_PROMPT+=" Include ticket ID '$TICKET'."
[[ -n $SCOPE  ]] && SYSTEM_PROMPT+=" Infer scope='$SCOPE'."
debug "System prompt: $SYSTEM_PROMPT"

# ── AI generation settings ──────────────────────────────────────────────────
MAX_TRIES=3
LAST_MSG=""

# Per-run temp file, created once per hook invocation (fixed /tmp/gpt.json
# raced parallel commits). BSD mktemp requires trailing Xs, hence no suffix.
# EXIT trap so set -e aborts never leak /tmp files.
GPT_TMP_JSON=$(mktemp /tmp/gptcommit.XXXXXX)
trap 'rm -f "$GPT_TMP_JSON"' EXIT

generate() {
  info "🤖  Generating AI draft…"
  local prompt payload response code attempt wait http
  prompt="Generate a Conventional Commit message"
  [[ -n $SCOPE ]] && prompt+=" for scope '$SCOPE'"
  prompt+=":\n\`\`\`diff
$DIFF
\`\`\`"
  [[ -n $LAST_MSG ]] && prompt+="\nPrevious suggestion: $LAST_MSG\nProvide a different variation."

  payload=$(jq -nc \
    --arg m "gpt-4o-mini" \
    --argjson t 0.2 \
    --arg sys "$SYSTEM_PROMPT" \
    --arg usr "$prompt" \
    '{model:$m,temperature:$t,messages:[{role:"system",content:$sys},{role:"user",content:$usr}]}')

  for attempt in $(seq 1 $MAX_TRIES); do
    # `|| true`: curl failure must not trip set -e; the code guard below
    # treats unparseable output as a non-retryable break with fallback text.
    http=$(curl -sS -w "%{http_code}" -o "$GPT_TMP_JSON" \
      -H "Authorization: Bearer $OPENAI_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$payload" \
      https://api.openai.com/v1/chat/completions || true)
    code=$(printf '%s' "$http" | tail -c 3)
    [[ "$code" =~ ^[0-9]{3}$ ]] || code=000
    response=$(< "$GPT_TMP_JSON")
    if (( code == 200 )); then
      break
    elif (( code == 429 || code >= 500 )); then
      wait=$((2**attempt))
      warn "HTTP $code; retrying in ${wait}s..."
      sleep $wait
    else
      break
    fi
  done

  jq -r '.choices[0].message.content // empty' <<<"$response"
}

# ── Generate & clean up ──────────────────────────────────────────────────────
COMMIT_MSG=$(generate)
COMMIT_MSG=$(sed '/^[[:space:]]*$/d' <<<"$COMMIT_MSG")
[[ -z $COMMIT_MSG ]] && COMMIT_MSG="chore: update $STAGED_COUNT files"

# ── Interactive accept/regenerate/skip ─────────────────────────────────────
# No controlling terminal (GUI clients, IDEs): never block on /dev/tty —
# the redirect would fail under set -e and abort the commit. Keep the
# generated message and let the commit proceed.
if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
  info "No TTY detected; keeping generated message without prompting."
  printf '%s\n' "$COMMIT_MSG" > "$MSG_FILE"
  exit 0
fi
TTY=/dev/tty; tries=0
while true; do
  printf '[AI] Proposed commit message:\n---\n%s\n---\n' "$COMMIT_MSG" >"$TTY"
  printf 'Accept (y), Regenerate (r), Skip (s)? [y/r/s] '           >"$TTY"
  read -r choice <"$TTY"
  case "$choice" in
    y|Y) break ;;
    r|R)
      if (( tries < MAX_TRIES )); then
        ((tries++)); LAST_MSG="$COMMIT_MSG"
        printf '[DEBUG] Regenerating (%d)...\n' "$tries" >/dev/tty
        COMMIT_MSG=$(generate)
        COMMIT_MSG=$(sed '/^[[:space:]]*$/d' <<<"$COMMIT_MSG")
      else
        warn "Max regenerations reached."; break
      fi
      ;;
    s|S) exit 0 ;;
    *) break ;;
  esac
done

# ── Write final commit message ──────────────────────────────────────────────
printf '%s\n' "$COMMIT_MSG" > "$MSG_FILE"
info "🎉  Commit message ready in $MSG_FILE"