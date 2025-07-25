#!/usr/bin/env bash
set -euo pipefail
# Uncomment for very verbose tracing:
# set -x

# ── Configuration ───────────────────────────────────────────────────────────
DEBUG=${GPTCOMMIT_DEBUG:-false}   # only true if you do: export GPTCOMMIT_DEBUG=true

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Absolute path to this script (for hook stub)
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ── Logging ─────────────────────────────────────────────────────────────────
debug() {
  # IMPORTANT: use an if so that failure to match doesn’t return non-zero
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
  help            Show this help message
  install         Install stub into .git/hooks/prepare-commit-msg

With no COMMAND, runs the AI-powered prepare-commit-msg hook as before.
EOF
}

# ── INSTALL: write a tiny stub into prepare-commit-msg ───────────────────────
install_hook() {
  # 1) Find the repo’s .git dir (absolute)
  raw=$(git rev-parse --git-dir 2>/dev/null) || {
    warn "Not inside a Git repository."
    exit 1
  }
  [[ "$raw" = /* ]] && GIT_DIR="$raw" || GIT_DIR="$PWD/$raw"
  HOOK="$GIT_DIR/hooks/prepare-commit-msg"

  # 2) Already our stub?
  if [ -f "$HOOK" ] && grep -qxF "exec \"$SCRIPT_PATH\" \"\\\$@\"" "$HOOK"; then
    info "prepare-commit-msg hook already installed. Skipping."
    exit 0
  fi

  # 3) If something else is there, back it up or bail
  if [ -e "$HOOK" ]; then
    warn "Existing prepare-commit-msg hook found at $HOOK"
    cat <<EOF >&2
To install gptcommit.sh:
  1) Backup the old hook:
       mv "$HOOK" "${HOOK}.backup"
  2) Re-run:
       ./"$(basename "$SCRIPT_PATH")" install

Or merge it manually, then:
  ln -sf "$SCRIPT_PATH" "$HOOK"
  chmod +x "$HOOK"
EOF
    exit 0
  fi

  # 4) Write our 4-line stub
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
MSG_FILE=$1
SOURCE=${2:-}

info "🏃‍♂️  gptcommit hook running…"
debug "MSG_FILE=$MSG_FILE"
debug "SOURCE=$SOURCE"

# ── Only for fresh commits (SOURCE empty or "message") ────────────────────────
if [[ -n "$SOURCE" && "$SOURCE" != "message" ]]; then
  debug "Skipping AI hook for source='$SOURCE'"
  exit 0
fi

# ── Skip during a rebase ─────────────────────────────────────────────────────
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
info "📂  Gathering staged files…"
STAGED_FILES=$(git diff --cached --name-only)
STAGED_COUNT=$(grep -cve '^$' <<<"$STAGED_FILES")
info "📂  Found $STAGED_COUNT staged file(s)"
if (( STAGED_COUNT == 0 )); then
  warn "No staged changes; skipping AI hook."
  exit 0
fi
debug "Staged files:\n$STAGED_FILES"

info "📝  Extracting staged diff…"
DIFF=$(git diff --cached --unified=5)
debug "Diff (truncated):\n${DIFF:0:200}…"

# ── Fallback if no additions ────────────────────────────────────────────────
if ! grep -q '^+[^+]' <<<"$DIFF"; then
  FALLBACK="feat: add $(basename "$(head -n1 <<<"$STAGED_FILES")")"
  info "🎯  No additions; using fallback: $FALLBACK"
  printf '%s\n' "$FALLBACK" > "$MSG_FILE"
  exit 0
fi

# ── Branch & ticket inference ───────────────────────────────────────────────
info "🌿  Parsing branch for ticket ID…"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ $BRANCH =~ ([A-Z]+-[0-9]+) ]]; then
  TICKET=${BASH_REMATCH[1]}
  info "🔖  Detected ticket: $TICKET"
else
  TICKET=""
  info "🔖  No ticket ID found"
fi

# ── Scope inference ─────────────────────────────────────────────────────────
info "💡  Inferring scope…"
IFS=$'\n' read -rd '' -a FILE_ARR <<<"$STAGED_FILES" || true
if (( ${#FILE_ARR[@]} )); then
  SCOPE=$(cut -d/ -f1 <<<"${FILE_ARR[0]}")
  info "💡  Inferred scope: $SCOPE"
else
  SCOPE=""
  info "💡  No scope inferred"
fi

# ── Build AI system prompt & generate ───────────────────────────────────────
SYSTEM_PROMPT="You are an expert assistant writing git commit messages per Conventional Commits: type(scope?): subject. Subject ≤50 chars, imperative mood."
[[ -n $SCOPE  ]] && SYSTEM_PROMPT+=" Infer scope='$SCOPE'."
[[ -n $TICKET ]] && SYSTEM_PROMPT+=" Include ticket '$TICKET'."
debug "System prompt: $SYSTEM_PROMPT"

MAX_TRIES=3
LAST_MSG=""

generate() {
  info "🤖  Generating AI draft…"
  local prompt payload attempt wait response
  prompt="Generate a Conventional Commit message"
  [[ -n $SCOPE ]]   && prompt+=" for scope '$SCOPE'"
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
    http=$(curl -sS -w "%{http_code}" -o /tmp/gpt.json \
      -H "Authorization: Bearer $OPENAI_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$payload" \
      https://api.openai.com/v1/chat/completions)
    code=${http: -3}
    response=$(< /tmp/gpt.json)
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

COMMIT_MSG=$(generate)
COMMIT_MSG=$(sed '/^[[:space:]]*$/d' <<<"$COMMIT_MSG")
[[ -z $COMMIT_MSG ]] && COMMIT_MSG="chore: update $STAGED_COUNT files"

# ── Interactive accept/regenerate/skip ─────────────────────────────────────
TTY=/dev/tty
tries=0
while true; do
  printf '[AI] Proposed commit message:\n---\n%s\n---\n' "$COMMIT_MSG" >"$TTY"
  printf 'Accept (y), Regenerate (r), Skip (s)? [y/r/s] '           >"$TTY"
  read -r choice <"$TTY"
  case "$choice" in
    y|Y) break ;;
    r|R)
      if (( tries < MAX_TRIES )); then
        ((tries++))
        LAST_MSG="$COMMIT_MSG"
        printf '[DEBUG] Regenerating (%d)...\n' "$tries" >/dev/tty
        COMMIT_MSG=$(generate)
        COMMIT_MSG=$(sed '/^[[:space:]]*$/d' <<<"$COMMIT_MSG")
      else
        warn "Max regenerations reached."
        break
      fi
      ;;
    s|S) exit 0 ;;
    *) break ;;
  esac
done

# ── Write final commit message ──────────────────────────────────────────────
printf '%s\n' "$COMMIT_MSG" > "$MSG_FILE"
info "🎉  Commit message ready in $MSG_FILE"