#!/usr/bin/env bash
set -euo pipefail

# Environment registry
# Format: "Label|ArgoCD Server URL"
ENVS=(
  "Alpha  (EU)|argo-mng.eu.postman-alpha.com"
  "Beta   (US)|argo-mng.us.postman-beta.com"
  "Stage  (US)|argo-mng.stage.us.ia.postmanlabs.com"
  "Prod   (US)|argo-mng.prod.us.ia.postmanlabs.com"
)

# Persists the selected environment between invocations.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/argoq"
STATE_FILE="${STATE_DIR}/current-env"

ensure_state_dir() {
  [[ -d "$STATE_DIR" ]] || mkdir -p "$STATE_DIR"
}

check_deps() {
  local missing=()
  for cmd in argocd fzf jq; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    echo "Error: missing required tools: ${missing[*]}" >&2
    exit 1
  fi
}

# Temp directory (auto-cleaned on exit / interrupt)
ARGOQ_TMPDIR=$(mktemp -d /tmp/argoq-XXXXXX)
trap 'rm -rf "$ARGOQ_TMPDIR"' EXIT INT TERM HUP

# Optional tool detection
_has()  { command -v "$1" &>/dev/null; }
_mktmp() {
  local f; f=$(mktemp "$ARGOQ_TMPDIR"/XXXXXX) && mv "$f" "${f}.yaml" && echo "${f}.yaml"
}
_warn_once() {
  local key="__argoq_warned_$1"
  if [[ -z "${!key:-}" ]]; then
    printf '  (tip: install %s for a better experience)\n' "$1" >&2
    eval "$key=1"
  fi
}

# Resolve a diff-capable editor
# Priority: $ARGOQ_DIFF > nvim > $EDITOR > code/cursor > none
# Example: ARGOQ_DIFF=code argoq compare
_diff_editor() {
  # Highest priority: user's explicit override
  if [[ -n "${ARGOQ_DIFF:-}" ]]; then
    if _has "$ARGOQ_DIFF"; then
      echo "$ARGOQ_DIFF"; return
    else
      echo "Warning: ARGOQ_DIFF='$ARGOQ_DIFF' not found, falling back" >&2
    fi
  fi
  if _has nvim; then echo "nvim"; return; fi
  if [[ -n "${EDITOR:-}" ]] && _has "$EDITOR"; then
    echo "$EDITOR"; return
  fi
  if _has cursor; then echo "cursor"; return; fi
  if _has code;   then echo "code";   return; fi
  echo ""   # no editor found
}

# ── show_yaml: display YAML with syntax highlighting ─────────────
# Fallback chain: bat → cat (with notice)
show_yaml() {
  if _has bat; then
    bat --language=yaml --style=plain --paging=always
  else
    _warn_once bat
    cat
  fi
}

show_diff() {
  local file_a="$1" file_b="$2"
  local label_a="${3:-A}" label_b="${4:-B}"
  local editor
  editor=$(_diff_editor)

  if [[ "$editor" == "nvim" ]]; then
    nvim -d \
      -c "set readonly nomodifiable" \
      -c "windo set readonly nomodifiable" \
      "$file_a" "$file_b"
  elif [[ "$editor" == "vim" || "$editor" == "vi" ]]; then
    "$editor" -d \
      -c "set readonly nomodifiable" \
      -c "windo set readonly nomodifiable" \
      "$file_a" "$file_b"
  elif [[ "$editor" == "code" || "$editor" == "cursor" ]]; then
    "$editor" --diff "$file_a" "$file_b" --wait
  elif [[ -n "$editor" ]]; then
    # Unknown $EDITOR — try --diff first, fall back to opening both
    "$editor" --diff "$file_a" "$file_b" --wait 2>/dev/null \
      || "$editor" "$file_a" "$file_b"
  else
    # No editor at all
    if _has bat; then
      diff --color=always -u \
        --label "$label_a" --label "$label_b" \
        "$file_a" "$file_b" \
        | bat --style=plain --paging=always || true
    else
      _warn_once bat
      diff -u --label "$label_a" --label "$label_b" \
        "$file_a" "$file_b" | less || true
    fi
  fi
}

# ─────────────────────────────────────────────────────── Helpers ───────────────────────────────────────────────────────
current_env_label() {
  if [[ -f "$STATE_FILE" ]]; then
    awk -F'|' '{print $1}' "$STATE_FILE"
  fi
}

current_env_server() {
  if [[ -f "$STATE_FILE" ]]; then
    awk -F'|' '{print $2}' "$STATE_FILE"
  fi
}

cmd_whoami() {
  echo "┌─────────────────────────────────────────────────"

  # Selected environment
  local label server
  label="$(current_env_label)"
  server="$(current_env_server)"
  if [[ -n "$label" ]]; then
    echo "│ Environment:  $label  ($server)"
  else
    echo "│ Environment:  (none selected)"
  fi

  # User info from current session
  local user_info
  user_info=$(argocd account get-user-info --grpc-web 2>/dev/null) || true
  if [[ -n "$user_info" ]]; then
    local logged_in groups
    logged_in=$(echo "$user_info" | awk '/^Logged In:/ {print $NF}')
    groups=$(echo "$user_info" | awk -F': ' '/^Groups:/ {print $2}')
    echo "│ Logged in:    $logged_in"
    echo "│ Groups:       ${groups:--}"
  else
    echo "│ Logged in:    false"
  fi

  # All sessions
  echo "├─────────────────────────────────────────────────"
  echo "│ Sessions:"
  local contexts logged_in_servers=""
  contexts=$(argocd context 2>/dev/null | awk 'NR>1') || true
  if [[ -z "$contexts" ]]; then
    echo "│   (none)"
  else
    logged_in_servers=$(echo "$contexts" | awk '{print $NF}')
    while IFS= read -r ctx_line; do
      local marker ctx_server
      marker=$(echo "$ctx_line" | awk '{print ($1 == "*") ? "●" : " "}')
      ctx_server=$(echo "$ctx_line" | awk '{print $NF}')
      # Find label for this server
      local ctx_label="$ctx_server"
      for entry in "${ENVS[@]}"; do
        if [[ "${entry##*|}" == "$ctx_server" ]]; then
          ctx_label="${entry%%|*}"
          break
        fi
      done
      printf "│   %s %-20s  %s\n" "$marker" "$ctx_label" "$ctx_server"
    done <<< "$contexts"
  fi

  # Cache status — only for logged-in sessions
  echo "├─────────────────────────────────────────────────"
  echo "│ Cache:"
  local has_cache=false
  for entry in "${ENVS[@]}"; do
    local entry_label="${entry%%|*}"
    local entry_server="${entry##*|}"
    # Skip envs we're not logged into
    if ! echo "$logged_in_servers" | grep -qx "$entry_server"; then
      continue
    fi
    local cf="${STATE_DIR}/cache-$(echo "$entry_server" | tr '.' '-').json"
    if [[ -f "$cf" ]]; then
      has_cache=true
      local app_count age_str file_size
      if [[ -s "$cf" ]]; then
        app_count=$(jq 'length' "$cf" 2>/dev/null || echo "0")
      else
        app_count="0"
      fi
      local age
      age=$(cache_age "$cf")
      age_str=$(human_age "$age")
      file_size=$(du -h "$cf" 2>/dev/null | awk '{print $1}')
      printf "│   %-20s  %s app(s)  %s  %s\n" "$entry_label" "$app_count" "$age_str" "$file_size"
    fi
  done
  if [[ "$has_cache" == false ]]; then
    echo "│   (no cached data)"
  fi

  # Version
  echo "├─────────────────────────────────────────────────"
  local cli_version
  cli_version=$(argocd version --client --short 2>/dev/null || echo "unknown")
  echo "│ CLI:          $cli_version"
  echo "│ State dir:    $STATE_DIR"
  echo "└─────────────────────────────────────────────────"
}

# Save key=value pairs for a command so --continue can replay them.
save_last() {
  local cmd="$1"; shift
  ensure_state_dir
  local file="${STATE_DIR}/last-${cmd}"
  : > "$file"  # truncate
  while (( $# >= 2 )); do
    echo "$1=$2" >> "$file"
    shift 2
  done
}

load_last() {
  local cmd="$1" key="$2"
  local file="${STATE_DIR}/last-${cmd}"
  if [[ -f "$file" ]]; then
    awk -F'=' -v k="$key" '$1 == k {print substr($0, index($0,"=")+1); exit}' "$file"
  fi
}

has_last() {
  local cmd="$1"
  local file="${STATE_DIR}/last-${cmd}"
  [[ -f "$file" ]]
}

cmd_login() {
  local selection label server current_server

  current_server="$(current_env_server)"

  # Get list of already-logged-in servers from argocd contexts
  local logged_in_servers
  logged_in_servers=$(argocd context 2>/dev/null | awk 'NR>1 {print $NF}') || true

  # Build the fzf list with status indicators:
  #   ● = current env   ✓ = logged in (can switch)   · = not logged in
  local fzf_input
  fzf_input=$(
    for entry in "${ENVS[@]}"; do
      local entry_label="${entry%%|*}"
      local entry_server="${entry##*|}"
      local marker="·"
      if [[ "$entry_server" == "$current_server" ]]; then
        marker="●"
      elif echo "$logged_in_servers" | grep -qx "$entry_server"; then
        marker="✓"
      fi
      printf "%s %-20s  %s\n" "$marker" "$entry_label" "$entry_server"
    done
  )

  local fzf_args=(
    --height=10
    --reverse
    --prompt="Select ArgoCD environment > "
    --header="● current  ✓ logged in (quick switch)  · needs SSO"
  )

  selection=$(echo "$fzf_input" | fzf "${fzf_args[@]}") || {
    echo "No selection made. Aborting."
    return 1
  }

  if [[ -z "$selection" ]]; then
    echo "No selection made. Aborting."
    return 1
  fi

  server=$(echo "$selection" | awk '{print $NF}')

  for entry in "${ENVS[@]}"; do
    local entry_server="${entry##*|}"
    if [[ "$entry_server" == "$server" ]]; then
      label="${entry%%|*}"
      break
    fi
  done

  echo ""
  echo "Selected: $label  ($server)"

  # Persist the choice
  ensure_state_dir
  echo "${label}|${server}" > "$STATE_FILE"

  # Check if already logged in -- just switch context
  if echo "$logged_in_servers" | grep -qx "$server"; then
    echo "Session exists. Switching context..."
    argocd context "$server" >/dev/null 2>&1
    echo "Switched to $label ($server)"
  else
    # Full SSO login
    echo "No existing session. Logging in via SSO..."
    echo "(This will open your browser for authentication)"
    echo ""
    argocd login "$server" --sso --grpc-web
    echo ""
    echo "Logged in to $label ($server)"
  fi
}

cmd_logout() {
  local server label
  server="$(current_env_server)"
  label="$(current_env_label)"

  if [[ -z "$server" ]]; then
    echo "No environment selected. Nothing to logout from."
    return 0
  fi

  echo "Logging out from $label ($server) ..."
  argocd logout "$server" 2>&1 || true
  argocd context "$server" --delete 2>/dev/null || true

  # Clear the saved environment and cache
  rm -f "$STATE_FILE"
  rm -f "${STATE_DIR}/cache-$(echo "$server" | tr '.' '-').json"

  echo "Logged out and cleared environment."
}

cmd_logout_all() {
  local servers
  servers=$(argocd context 2>/dev/null | awk 'NR>1 {print $NF}') || true

  if [[ -z "$servers" ]]; then
    echo "No active sessions found."
    rm -f "$STATE_FILE"
    return 0
  fi

  local count
  count=$(echo "$servers" | wc -l | tr -d ' ')
  echo "Logging out from $count environment(s)..."
  echo ""

  while IFS= read -r server; do
    echo "  Logout: $server"
    argocd logout "$server" 2>/dev/null || true
    argocd context "$server" --delete 2>/dev/null || true
    rm -f "${STATE_DIR}/cache-$(echo "$server" | tr '.' '-').json"
  done <<< "$servers"

  # Clear argoq state
  rm -f "$STATE_FILE"
  rm -f "${STATE_DIR}"/last-*

  echo ""
  echo "All sessions and cache cleared."
}

require_env() {
  local server
  server="$(current_env_server)"
  if [[ -z "$server" ]]; then
    echo "No environment selected. Run '$(basename "$0") login' first." >&2
    exit 1
  fi
  echo "$server"
}

CACHE_MAX_AGE=300  # 5 minutes

cache_file_for_env() {
  local server
  server="$(current_env_server)"
  # Sanitise server name for use as filename
  echo "${STATE_DIR}/cache-$(echo "$server" | tr '.' '-').json"
}

cache_age() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "none"
    return
  fi
  local now file_mtime age
  now=$(date +%s)
  # macOS stat vs GNU stat
  if stat -f '%m' /dev/null &>/dev/null; then
    file_mtime=$(stat -f '%m' "$file")
  else
    file_mtime=$(stat -c '%Y' "$file")
  fi
  age=$(( now - file_mtime ))
  echo "$age"
}

human_age() {
  local secs="$1"
  if [[ "$secs" == "none" ]]; then
    echo "no cache"
    return
  fi
  if (( secs < 60 )); then
    echo "${secs}s ago"
  elif (( secs < 3600 )); then
    echo "$(( secs / 60 ))m ago"
  else
    echo "$(( secs / 3600 ))h ago"
  fi
}

# Fetch app list JSON from ArgoCD and write to cache
refresh_cache() {
  local cache_file="$1"
  ensure_state_dir
  argocd app list --grpc-web -o json 2>/dev/null > "$cache_file"
}

build_table() {
  local cache_file="$1"
  jq -r '
    .[] |
    [
      .metadata.name,
      .spec.project,
      .spec.destination.namespace,
      (.status.sync.status   // "-"),
      (.status.health.status // "-"),
      ([.status.conditions // [] | .[] | .type] | if length > 0 then join(",") else "-" end)
    ] | @tsv
  ' "$cache_file" | sort | column -t -s $'\t'
}

show_app_detail() {
  local app_name="$1"
  local server
  server="$(current_env_server)"

  local json
  # Clean control characters that argocd sometimes embeds in JSON
  json=$(argocd app get "$app_name" --grpc-web -o json 2>/dev/null \
    | tr -d '\000-\010\013\014\016-\037') || {
    echo "Error: failed to fetch app details." >&2
    return 1
  }

  echo "$json" | jq -r '
    "┌─────────────────────────────────────────────────",
    "│ App:        \(.metadata.name)",
    "│ Project:    \(.spec.project)",
    "│ Namespace:  \(.spec.destination.namespace)",
    "│ Sync:       \(.status.sync.status // "-")",
    "│ Health:     \(.status.health.status // "-")",
    "│ URL:        https://'"$server"'/applications/\(.metadata.name)",
    "├─────────────────────────────────────────────────",
    "│ Sync Policy:",
    (if .spec.syncPolicy.automated then
      "│   automated  prune=\(.spec.syncPolicy.automated.prune // false)  selfHeal=\(.spec.syncPolicy.automated.selfHeal // false)"
    else
      "│   manual"
    end),
    "├─────────────────────────────────────────────────",
    "│ Sources:"
  '

  echo "$json" | jq -r '
    (.spec.sources // [.spec.source] | to_entries[] |
      "│   [\(.key + 1)] \(.value.repoURL)",
      "│       path=\(.value.path // "-")  target=\(.value.targetRevision // "-")"
    )
  '

  #  Conditions (if any)
  local cond_count
  cond_count=$(echo "$json" | jq '[.status.conditions // [] | .[] ] | length')
  if (( cond_count > 0 )); then
    echo "├─────────────────────────────────────────────────"
    echo "│ Conditions:"
    echo "$json" | jq -r '
      .status.conditions[]? |
      "│   ⚠ \(.type): \(.message)"
    '
  fi

  # Resources
  echo "├─────────────────────────────────────────────────"
  echo "│ Resources:"
  echo "│"
  {
    echo "KIND	NAMESPACE	NAME	STATUS	HEALTH"
    echo "$json" | jq -r '
      (.status.resources // [] | sort_by(.kind) | .[] |
        [.kind, (.namespace // "-"), .name, (.status // "-"), (.health.status // "-")]
        | @tsv
      )
    '
  } | column -t -s $'\t' | sed 's/^/│   /'
  echo "│"
  echo "└─────────────────────────────────────────────────"
}

cmd_apps() {
  local live=false continuing=false unhealthy=false
  for arg in "$@"; do
    case "$arg" in
      --live)      live=true ;;
      --continue)  continuing=true ;;
      --unhealthy) unhealthy=true ;;
    esac
  done

  require_env >/dev/null

  local app_name

  if [[ "$continuing" == true ]] && has_last apps; then
    app_name="$(load_last apps app_name)"
    if [[ -n "$app_name" ]]; then
      echo "Continuing: $app_name"
      app_action_menu "$app_name"
      return 0
    fi
    echo "No previous apps session found. Starting fresh."
  fi

  local label
  label="$(current_env_label)"

  ensure_state_dir
  local cache_file
  cache_file="$(cache_file_for_env)"
  local age
  age="$(cache_age "$cache_file")"

  # Decide: use cache or fetch live
  if [[ "$live" == true ]] || [[ "$age" == "none" ]] || (( age > CACHE_MAX_AGE )); then
    echo "Fetching apps from $label ..."
    refresh_cache "$cache_file" || {
      echo "Error: failed to fetch apps. Are you logged in?" >&2
      echo "Try: $(basename "$0") login" >&2
      return 1
    }
    age=0
  else
    echo "Using cached app list ($(human_age "$age")). Use --live to refresh."
    # Kick off a background refresh if cache is older than half the max age
    if (( age > CACHE_MAX_AGE / 2 )); then
      ( refresh_cache "$cache_file" & ) 2>/dev/null
    fi
  fi

  local table
  table=$(build_table "$cache_file")

  if [[ -z "$table" ]]; then
    echo "No applications found."
    return 0
  fi

  # Filter to only troubled apps if --unhealthy
  # Catches: not Synced, not Healthy, or has error conditions
  # Excludes: Progressing (actively deploying, not broken)
  if [[ "$unhealthy" == true ]]; then
    local filtered
    filtered=$(echo "$table" | awk '($4 != "Synced" || $5 != "Healthy" || $6 != "-") && $5 != "Progressing"')
    if [[ -z "$filtered" ]]; then
      echo "All apps are healthy and synced (no conditions)."
      return 0
    fi
    table="$filtered"
  fi

  local count
  count=$(echo "$table" | wc -l | tr -d ' ')

  local age_str
  age_str="$(human_age "$(cache_age "$cache_file")")"
  local header="NAME  PROJECT  NAMESPACE  SYNC  HEALTH  CONDITIONS"
  local filter_tag=""
  [[ "$unhealthy" == true ]] && filter_tag=" · unhealthy only"

  local selection
  selection=$(echo "$table" | \
    fzf --header="$header  [$count app(s) in $label · cached $age_str${filter_tag}]" \
        --reverse \
        --height=80% \
        --prompt="Search apps > " \
  ) || return 0

  if [[ -z "$selection" ]]; then
    return 0
  fi

  app_name=$(echo "$selection" | awk '{print $1}')

  save_last apps app_name "$app_name"

  app_action_menu "$app_name"
}

app_action_menu() {
  local app_name="$1"

  echo ""
  local action
  action=$(printf 'detail      Show app summary (sync, health, resources)\nopen        Open in ArgoCD UI (browser)\nlogs        Stream logs from pods\nmanifests   View manifests (live/git)\nresources   Drill into resources (live/git/diff)\nhistory     Show deployment history' | \
    fzf --height=10 --reverse \
        --prompt="Action for $app_name > " \
        --header="Pick an action (or Esc to exit)" \
  ) || return 0
  action=$(echo "$action" | awk '{print $1}')

  case "$action" in
    detail)
      echo ""
      show_app_detail "$app_name"
      ;;
    open)
      local server
      server="$(current_env_server)"
      local url="https://${server}/applications/${app_name}"
      echo "Opening: $url"
      open "$url"
      ;;
    logs)
      cmd_logs --for "$app_name"
      ;;
    manifests)
      cmd_manifests --for "$app_name"
      ;;
    resources)
      cmd_resources --for "$app_name"
      ;;
    history)
      cmd_history --for "$app_name"
      ;;
  esac
}

cmd_open() {
  local continuing=false
  if [[ "${1:-}" == "--continue" ]]; then
    continuing=true
  fi

  local server
  require_env >/dev/null
  server="$(current_env_server)"

  local app_name

  if [[ "$continuing" == true ]] && has_last open; then
    app_name="$(load_last open app_name)"
    if [[ -z "$app_name" ]]; then
      echo "No previous open session found. Starting fresh."
      continuing=false
    fi
  fi

  if [[ "$continuing" == false ]]; then
    app_name=$(pick_app "Open in browser") || return 0
  fi

  save_last open app_name "$app_name"

  local url="https://${server}/applications/${app_name}"
  echo "Opening: $url"
  open "$url"
}

cmd_logs() {
  local continuing=false given_app=""
  while (( $# )); do
    case "$1" in
      --continue) continuing=true; shift ;;
      --for)      given_app="${2:-}"; shift 2 ;;
      *)          shift ;;
    esac
  done

  require_env >/dev/null

  local app_name scope_type res_kind res_namespace res_name container choice filter_str

  if [[ "$continuing" == true ]] && has_last logs; then
    app_name="$(load_last logs app_name)"
    scope_type="$(load_last logs scope_type)"
    res_kind="$(load_last logs res_kind)"
    res_name="$(load_last logs res_name)"
    res_namespace="$(load_last logs res_namespace)"
    container="$(load_last logs container)"
    choice="$(load_last logs choice)"
    filter_str="$(load_last logs filter_str)"

    # Backward compat old state without scope_type
    if [[ -z "$scope_type" ]]; then
      if [[ -n "$res_kind" && -n "$res_name" ]]; then
        scope_type="resource"
      else
        scope_type="all"
      fi
    fi

    if [[ -z "$app_name" || -z "$choice" ]]; then
      echo "No previous logs session found. Starting fresh."
      continuing=false
    else
      local scope_desc="all pods"
      [[ "$scope_type" == "resource" ]] && scope_desc="$res_kind/$res_name"
      [[ "$scope_type" == "namespace" ]] && scope_desc="ns:$res_namespace"
      echo "Continuing: ${scope_desc}${container:+ ($container)}  [app: $app_name, mode: $choice]"
    fi
  fi

  if [[ "$continuing" == false ]]; then
    # Step 1: pick an app
    if [[ -n "$given_app" ]]; then
      app_name="$given_app"
    else
      app_name=$(pick_app "Select app for logs") || return 0
    fi

    # Step 2: fetch resources and build scope picker
    echo "Fetching resources for $app_name ..."
    local app_json
    app_json=$(argocd app get "$app_name" --grpc-web -o json 2>/dev/null \
      | tr -d '\000-\010\013\014\016-\037') || {
      echo "Error: failed to fetch app details." >&2
      return 1
    }

    # Loggable resources
    local resource_table
    resource_table=$(echo "$app_json" | jq -r '
      [.status.resources // [] | .[]
        | select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet"
                 or .kind == "Pod" or .kind == "ReplicaSet" or .kind == "Job" or .kind == "CronJob")
        | [.kind, (.namespace // "-"), .name, (.health.status // "-")]
        | @tsv
      ] | sort | .[]
    ' | column -t -s $'\t')

    local namespaces
    namespaces=$(echo "$app_json" | jq -r '
      [.status.resources // [] | .[] | .namespace // empty] | unique | .[]
    ')

    if [[ -z "$resource_table" ]]; then
      echo "No loggable resources found. Falling back to app-level logs..."
      scope_type="all"
      res_kind="" ; res_name="" ; res_namespace=""
    else
      # Build the scope picker list
      local scope_lines
      scope_lines="[ALL]       -              (app-wide, all pods)"

      while IFS= read -r ns; do
        [[ -z "$ns" ]] && continue
        printf -v line "[NS]        %-14s (all resources in namespace)" "$ns"
        scope_lines+=$'\n'"$line"
      done <<< "$namespaces"

      scope_lines+=$'\n'"$resource_table"

      local scope_selection
      scope_selection=$(echo "$scope_lines" | \
        fzf --header="KIND        NAMESPACE      NAME / SCOPE                   [logs for $app_name]" \
            --reverse --height=50% \
            --prompt="Select scope > "
      ) || return 0

      # Parse the selection
      local scope_tag
      scope_tag=$(echo "$scope_selection" | awk '{print $1}')

      if [[ "$scope_tag" == "[ALL]" ]]; then
        scope_type="all"
        res_kind="" ; res_name="" ; res_namespace=""
      elif [[ "$scope_tag" == "[NS]" ]]; then
        scope_type="namespace"
        res_namespace=$(echo "$scope_selection" | awk '{print $2}')
        res_kind="" ; res_name=""
      else
        scope_type="resource"
        res_kind=$(echo "$scope_selection" | awk '{print $1}')
        res_namespace=$(echo "$scope_selection" | awk '{print $2}')
        res_name=$(echo "$scope_selection" | awk '{print $3}')
      fi
    fi

    #  Step 3: probe containers and let user pick
    container=""
    echo ""
    echo "Checking containers..."

    local probe_args=("$app_name" --grpc-web --tail 1)
    if [[ "$scope_type" == "resource" ]]; then
      probe_args+=(--kind "$res_kind" --name "$res_name" --namespace "$res_namespace")
    elif [[ "$scope_type" == "namespace" ]]; then
      probe_args+=(--namespace "$res_namespace")
    fi

    local probe_output
    probe_output=$(argocd app logs "${probe_args[@]}" 2>&1)

    if echo "$probe_output" | grep -q "a container name must be specified"; then
      local containers_raw
      containers_raw=$(echo "$probe_output" | grep -o '\[.*\]' | tr -d '[]')
      local containers
      # shellcheck disable=SC2206
      # https://www.shellcheck.net/wiki/SC2206
      containers=($containers_raw)

      if (( ${#containers[@]} > 0 )); then
        echo "Pick a container:"
        echo ""
        local container_pick
        container_pick=$( (printf '[ALL]  All containers\n'; printf '%s\n' "${containers[@]}") | \
          fzf --height=12 --reverse --prompt="Container > " \
              --header="Containers for ${res_name:-$app_name}"
        ) || return 0

        if [[ "$container_pick" == "[ALL]"* ]]; then
          container=""
        else
          container="$container_pick"
        fi
      fi
    else
      echo "Single container detected."
    fi

    # Step 4: pick log mode
    echo ""
    local scope_label="$app_name"
    [[ "$scope_type" == "resource" ]] && scope_label="$res_kind/$res_name"
    [[ "$scope_type" == "namespace" ]] && scope_label="ns:$res_namespace"

    local log_mode
    log_mode=$(printf '%s\n' \
      "last-100       Last 100 lines" \
      "last-500       Last 500 lines" \
      "last-1000      Last 1000 lines" \
      "since-1h       Since 1 hour ago" \
      "since-6h       Since 6 hours ago" \
      "since-24h      Since 24 hours ago" \
      "follow         Follow (stream live)" \
      "follow-filter  Follow + filter keyword" \
      "search         Search logs (grep, last 5000 lines)" \
      "previous       Previous container (crashed/restarted)" \
    | fzf --height=14 --reverse \
          --prompt="Log mode > " \
          --header="How to view logs for $scope_label?"
    ) || return 0

    choice=$(echo "$log_mode" | awk '{print $1}')

    filter_str=""
    if [[ "$choice" == "follow-filter" || "$choice" == "search" ]]; then
      read -rp "Filter string: " filter_str
      if [[ -z "$filter_str" ]]; then
        echo "No filter provided, aborting." >&2
        return 1
      fi
    fi

    # state for --continue
    save_last logs \
      app_name "$app_name" \
      scope_type "$scope_type" \
      res_kind "$res_kind" \
      res_name "$res_name" \
      res_namespace "$res_namespace" \
      container "$container" \
      choice "$choice" \
      filter_str "$filter_str"
  fi

  local log_args=("$app_name" --grpc-web)

  if [[ "$scope_type" == "resource" ]]; then
    log_args+=(--kind "$res_kind" --name "$res_name" --namespace "$res_namespace")
  elif [[ "$scope_type" == "namespace" ]]; then
    log_args+=(--namespace "$res_namespace")
  fi
  # "all" scope: no kind/name/namespace filters

  [[ -n "$container" ]] && log_args+=(-c "$container")

  case "$choice" in
    last-100)      log_args+=(--tail 100) ;;
    last-500)      log_args+=(--tail 500) ;;
    last-1000)     log_args+=(--tail 1000) ;;
    since-1h)      log_args+=(--since-seconds 3600) ;;
    since-6h)      log_args+=(--since-seconds 21600) ;;
    since-24h)     log_args+=(--since-seconds 86400) ;;
    follow)        log_args+=(--follow) ;;
    follow-filter) log_args+=(--follow --filter "$filter_str") ;;
    search)        log_args+=(--tail 5000 --filter "$filter_str") ;;
    previous)      log_args+=(-p --tail 500) ;;
    *)             log_args+=(--tail 100) ;;
  esac

  echo ""
  local scope_header="$app_name (all pods)"
  [[ "$scope_type" == "resource" ]] && scope_header="$res_kind/$res_name"
  [[ "$scope_type" == "namespace" ]] && scope_header="ns:$res_namespace"
  echo "── Logs: ${scope_header}${container:+ ($container)} [$choice] ──"
  echo ""

  local log_output
  log_output=$(argocd app logs "${log_args[@]}" 2>&1) || true

  if [[ -z "$log_output" ]]; then
    echo "No log output returned."
    return 0
  fi

  # Detect "previous terminated container not found"
  if echo "$log_output" | grep -q "previous terminated container.*not found"; then
    local not_found_count
    not_found_count=$(echo "$log_output" | grep -c "not found")
    echo "No previous (crashed) container logs available."
    echo "  $not_found_count pod(s) checked — none have restarted."
    echo ""
    echo "This means the containers haven't crashed recently."
    echo "Try 'last-100' or 'follow' to see current logs instead."
    return 0
  fi

  echo "$log_output" | format_log_lines
}

# Parses JSON log lines into a compact
# Falls back to raw output for non-JSON lines.
format_log_lines() {
  jq -R -r '
    def colorize_level:
      if   . == "error"   then "\u001b[31m\(. | ascii_upcase)\u001b[0m"
      elif . == "warn"    then "\u001b[33m\(. | ascii_upcase)\u001b[0m"
      elif . == "warning" then "\u001b[33m\(. | ascii_upcase)\u001b[0m"
      elif . == "info"    then "\u001b[32m\(. | ascii_upcase)\u001b[0m"
      elif . == "debug"   then "\u001b[36m\(. | ascii_upcase)\u001b[0m"
      else                     "\u001b[37m\(. | ascii_upcase)\u001b[0m"
      end;

    def format_ts:
      if . == null then "--------"
      elif type == "string" then (split("T") | if length > 1 then .[1] | split(".")[0] | split("+")[0] | split("Z")[0] else .[0] end)
      elif . > 9999999999 then (. / 1000 | strftime("%H:%M:%S"))
      else (. | strftime("%H:%M:%S"))
      end;

    def format_event:
      if   type == "string" then .
      elif type == "object" then
        (.message // .error.message // (. | tostring))
      else (. | tostring)
      end;

    def extract_msg:
      (.event // .msg // .message // "-") | format_event;

    (fromjson? // null) as $p |
    if $p and ($p | type) == "object" then
      "\u001b[90m\($p.timestamp // $p.ts // $p.time | format_ts)\u001b[0m \($p.level // $p.severity // "-" | colorize_level)  \($p | extract_msg)"
    else .
    end
  '
}

# pick an app from the cached list
pick_app() {
  local label prompt="${1:-Select app}"
  label="$(current_env_label)"

  ensure_state_dir
  local cache_file
  cache_file="$(cache_file_for_env)"

  local age
  age="$(cache_age "$cache_file")"
  if [[ "$age" == "none" ]] || (( age > CACHE_MAX_AGE )); then
    echo "Fetching apps from $label ..." >&2
    refresh_cache "$cache_file" || {
      echo "Error: failed to fetch apps. Are you logged in?" >&2
      return 1
    }
  fi

  local table
  table=$(build_table "$cache_file")

  if [[ -z "$table" ]]; then
    echo "No applications found." >&2
    return 1
  fi

  local count
  count=$(echo "$table" | wc -l | tr -d ' ')
  local header="NAME  PROJECT  NAMESPACE  SYNC  HEALTH  CONDITIONS"

  # Pre-populate fzf with the last-used app name for quick re-selection
  local fzf_args=(
    --header="$header  [$count app(s) in $label]"
    --reverse
    --height=80%
    --prompt="$prompt > "
  )

  local selection
  selection=$(echo "$table" | fzf "${fzf_args[@]}") || return 1

  if [[ -z "$selection" ]]; then
    return 1
  fi

  echo "$selection" | awk '{print $1}'
}

cmd_manifests() {
  local continuing=false given_app=""
  while (( $# )); do
    case "$1" in
      --continue) continuing=true; shift ;;
      --for)      given_app="${2:-}"; shift 2 ;;
      *)          shift ;;
    esac
  done

  require_env >/dev/null

  local app_name source selected_kind_name

  if [[ "$continuing" == true ]] && has_last manifests; then
    app_name="$(load_last manifests app_name)"
    source="$(load_last manifests source)"
    selected_kind_name="$(load_last manifests resource)"

    if [[ -z "$app_name" || -z "$source" ]]; then
      echo "No previous manifests session found. Starting fresh."
      continuing=false
    else
      echo "Continuing: $app_name  source=$source${selected_kind_name:+  resource=$selected_kind_name}"
    fi
  fi

  if [[ "$continuing" == false ]]; then
    if [[ -n "$given_app" ]]; then
      app_name="$given_app"
    else
      app_name=$(pick_app "Select app for manifests") || return 0
    fi

    # Pick source: live vs git
    echo ""
    source=$(printf 'live  (what is running in the cluster)\ngit   (desired state from repo)' | \
      fzf --height=6 --reverse \
          --prompt="Manifest source > " \
          --header="Pick manifest source for $app_name" \
    ) || return 0
    source=$(echo "$source" | awk '{print $1}')
  fi

  echo ""
  echo "Fetching $source manifests for $app_name ..."

  local manifests
  manifests=$(argocd app manifests "$app_name" --grpc-web --source "$source" 2>/dev/null) || {
    echo "Error: failed to fetch manifests." >&2
    return 1
  }

  if [[ -z "$manifests" ]]; then
    echo "No manifests returned."
    return 0
  fi

  # Build an index of resources from the YAML stream
  local index
  index=$(echo "$manifests" | awk '
    BEGIN { doc=0; kind=""; name=""; ns="" }
    /^---/ { if (kind != "") printf "%d\t%s/%s\t%s\n", doc, kind, name, ns; doc++; kind=""; name=""; ns="" }
    /^kind:/ { kind=$2 }
    /^  name:/ && name == "" { name=$2 }
    /^  namespace:/ { ns=$2 }
    END { if (kind != "") printf "%d\t%s/%s\t%s\n", doc, kind, name, ns }
  ')

  if [[ -z "$index" ]]; then
    echo "$manifests" | show_yaml
    return 0
  fi

  local count
  count=$(echo "$index" | wc -l | tr -d ' ')

  # On --continue with a saved resource, skip the picker
  if [[ "$continuing" == false ]] || [[ -z "$selected_kind_name" ]]; then
    local pick_list
    pick_list=$(
      echo "[ALL]  View all $count manifests"
      echo "$index" | awk -F'\t' '{printf "%-40s  ns=%s\n", $2, ($3 == "" ? "-" : $3)}'
    )

    local selection
    selection=$(echo "$pick_list" | \
      fzf --height=60% --reverse \
          --prompt="Pick resource > " \
          --header="$count resource(s) in $app_name ($source)" \
    ) || return 0

    if echo "$selection" | grep -q '^\[ALL\]'; then
      selected_kind_name="ALL"
    else
      selected_kind_name=$(echo "$selection" | awk '{print $1}')
    fi
  fi

  # Save selections for --continue
  save_last manifests \
    app_name "$app_name" \
    source "$source" \
    resource "$selected_kind_name"

  if [[ "$selected_kind_name" == "ALL" ]]; then
    echo "$manifests" | show_yaml
    return 0
  fi

  # Find the matching doc index
  local doc_idx
  doc_idx=$(echo "$index" | awk -F'\t' -v target="$selected_kind_name" '$2 == target {print $1; exit}')

  if [[ -z "$doc_idx" ]]; then
    echo "Could not locate resource '$selected_kind_name'. Showing all manifests."
    echo "$manifests" | show_yaml
    return 0
  fi

  # Extract that single YAML document from the stream
  local single_doc
  single_doc=$(echo "$manifests" | awk -v target="$doc_idx" '
    BEGIN { doc=0; printing=0 }
    /^---/ { if (printing) exit; doc++ }
    doc == target { printing=1 }
    printing { print }
  ')

  echo ""
  echo "$single_doc" | show_yaml
}

#  drill into an apps k8s resources
cmd_resources() {
  local continuing=false given_app=""
  while (( $# )); do
    case "$1" in
      --continue) continuing=true; shift ;;
      --for)      given_app="${2:-}"; shift 2 ;;
      *)          shift ;;
    esac
  done

  require_env >/dev/null

  local app_name

  if [[ "$continuing" == true ]] && has_last resources; then
    app_name="$(load_last resources app_name)"
    if [[ -z "$app_name" ]]; then
      echo "No previous resources session found. Starting fresh."
      continuing=false
    else
      echo "Continuing with app: $app_name"
    fi
  fi

  if [[ "$continuing" == false ]]; then
    if [[ -n "$given_app" ]]; then
      app_name="$given_app"
    else
      app_name=$(pick_app "Select app for resources") || return 0
    fi
  fi

  # Fetch the apps resource list
  echo "Fetching resources for $app_name ..."
  local app_json
  app_json=$(argocd app get "$app_name" --grpc-web -o json 2>/dev/null \
    | tr -d '\000-\010\013\014\016-\037') || {
    echo "Error: failed to fetch app details." >&2
    return 1
  }

  local res_table
  res_table=$(echo "$app_json" | jq -r '
    [.status.resources // [] | .[] |
      [.kind, (.group // "-"), (.namespace // "-"), .name, (.status // "-"), (.health.status // "-")]
      | @tsv
    ] | sort | .[]
  ' | column -t -s $'\t')

  if [[ -z "$res_table" ]]; then
    echo "No resources found for $app_name."
    return 0
  fi

  local count
  count=$(echo "$res_table" | wc -l | tr -d ' ')
  local header="KIND  GROUP  NAMESPACE  NAME  STATUS  HEALTH"

  #  user pick a resource
  local selection
  selection=$(echo "$res_table" | \
    fzf --header="$header  [$count resource(s) in $app_name]" \
        --reverse \
        --height=80% \
        --prompt="Select resource > " \
  ) || return 0

  if [[ -z "$selection" ]]; then
    return 0
  fi

  local res_kind res_group res_namespace res_name
  res_kind=$(echo "$selection" | awk '{print $1}')
  res_group=$(echo "$selection" | awk '{print $2}')
  res_namespace=$(echo "$selection" | awk '{print $3}')
  res_name=$(echo "$selection" | awk '{print $4}')

  [[ "$res_group" == "-" ]] && res_group=""
  [[ "$res_namespace" == "-" ]] && res_namespace=""

  save_last resources \
    app_name "$app_name" \
    res_kind "$res_kind" \
    res_group "$res_group" \
    res_namespace "$res_namespace" \
    res_name "$res_name"

  # Action picker
  echo ""
  echo "Resource: $res_kind/$res_name${res_namespace:+  (ns: $res_namespace)}"
  echo ""
  local action
  action=$(printf 'live   View live manifest (what is running)\ngit    View desired manifest (from git)\ndiff   Compare live vs desired (side-by-side)' | \
    fzf --height=7 --reverse \
        --prompt="Action > " \
        --header="What do you want to see?" \
  ) || return 0
  action=$(echo "$action" | awk '{print $1}')

  echo ""

  case "$action" in
    live)
      echo "── Live manifest: $res_kind/$res_name ──"
      echo ""
      extract_resource_manifest "$app_name" "$res_kind" "$res_group" "$res_namespace" "$res_name" "live" \
        | show_yaml
      ;;
    git)
      echo "── Desired manifest: $res_kind/$res_name ──"
      echo ""
      extract_resource_manifest "$app_name" "$res_kind" "$res_group" "$res_namespace" "$res_name" "git" \
        | show_yaml
      ;;
    diff)
      echo "── Diff (git vs live): $res_kind/$res_name ──"
      echo ""
      local git_manifest live_manifest
      git_manifest=$(extract_resource_manifest "$app_name" "$res_kind" "$res_group" "$res_namespace" "$res_name" "git")
      live_manifest=$(extract_resource_manifest "$app_name" "$res_kind" "$res_group" "$res_namespace" "$res_name" "live")

      local tmp_git tmp_live
      tmp_git=$(_mktmp)
      tmp_live=$(_mktmp)

      echo "${git_manifest:-# (no git manifest)}" > "$tmp_git"
      echo "${live_manifest:-# (no live manifest)}" > "$tmp_live"

      show_diff "$tmp_git" "$tmp_live" "git (desired)" "live (running)"
      ;;
  esac
}

# Extract a single resource manifest 
extract_resource_manifest() {
  local app_name="$1" kind="$2" group="$3" namespace="$4" name="$5" source="$6"

  local manifests
  manifests=$(argocd app manifests "$app_name" --grpc-web --source "$source" 2>/dev/null)

  # Parse the YAML stream and find the matching document
  # We match on kind + apiVersion (group) + metadata.name + metadata.namespace
  echo "$manifests" | awk -v target_kind="$kind" -v target_name="$name" -v target_ns="$namespace" -v target_group="$group" '
    BEGIN { doc=""; kind=""; mname=""; ns=""; apigroup=""; found=0 }

    function extract_group(apiversion) {
      # apiVersion "apps/v1" -> group "apps"; "v1" -> group ""
      n = split(apiversion, parts, "/")
      return (n > 1) ? parts[1] : ""
    }

    function group_matches() {
      if (target_group == "" || target_group == "-") return 1
      return (apigroup == target_group)
    }

    /^---/ {
      if (found) { print doc; exit }
      if (kind == target_kind && mname == target_name && group_matches() && (target_ns == "" || ns == target_ns)) {
        found=1; print doc; exit
      }
      doc=""; kind=""; mname=""; ns=""; apigroup=""
      next
    }

    { doc = (doc == "" ? $0 : doc "\n" $0) }

    /^kind:/ { kind=$2 }
    /^apiVersion:/ { apigroup = extract_group($2) }
    /^  name:/ && mname == "" { mname=$2 }
    /^  namespace:/ { ns=$2 }

    END {
      if (!found && kind == target_kind && mname == target_name && group_matches() && (target_ns == "" || ns == target_ns)) {
        print doc
      }
    }
  '
}

cmd_history() {
  local continuing=false given_app=""
  while (( $# )); do
    case "$1" in
      --continue) continuing=true; shift ;;
      --for)      given_app="${2:-}"; shift 2 ;;
      *)          shift ;;
    esac
  done

  require_env >/dev/null

  local app_name

  if [[ "$continuing" == true ]] && has_last history; then
    app_name="$(load_last history app_name)"
    if [[ -z "$app_name" ]]; then
      echo "No previous history session found. Starting fresh."
      continuing=false
    else
      echo "Continuing with app: $app_name"
    fi
  fi

  if [[ "$continuing" == false ]]; then
    if [[ -n "$given_app" ]]; then
      app_name="$given_app"
    else
      app_name=$(pick_app "Select app for history") || return 0
    fi
  fi

  save_last history app_name "$app_name"

  echo "Fetching history for $app_name ..."
  echo ""

  local app_json
  app_json=$(argocd app get "$app_name" --grpc-web -o json 2>/dev/null \
    | tr -d '\000-\010\013\014\016-\037') || {
    echo "Error: failed to fetch app details." >&2
    return 1
  }

  local history_count
  history_count=$(echo "$app_json" | jq '.status.history | length')

  if [[ "$history_count" == "0" ]] || [[ "$history_count" == "null" ]]; then
    echo "No deployment history found for $app_name."
    return 0
  fi

  # Build a formatted history table (most recent first)
  local table
  table=$(echo "$app_json" | jq -r '
    .status.history | reverse | .[] |
    [
      (.id | tostring),
      .deployedAt,
      (if .initiatedBy.automated then "auto" else (.initiatedBy.username // "manual") end),
      (.revisions // [.revision // "-"] | map(.[0:20]) | join(", "))
    ] | @tsv
  ' | column -t -s $'\t')

  local header="ID  DEPLOYED_AT  TRIGGERED_BY  REVISIONS"

  # Show in fzf for browsing; selecting an entry shows full detail
  local selection
  selection=$(echo "$table" | \
    fzf --header="$header  [$history_count deploy(s) for $app_name]" \
        --reverse \
        --height=60% \
        --prompt="Select deploy > " \
  ) || return 0

  if [[ -z "$selection" ]]; then
    return 0
  fi

  local deploy_id
  deploy_id=$(echo "$selection" | awk '{print $1}')

  # Show full detail for the selected deploy
  echo ""
  echo "$app_json" | jq -r --arg id "$deploy_id" '
    .status.history[] | select(.id == ($id | tonumber)) |
    "┌─────────────────────────────────────────────────",
    "│ Deploy #\(.id)",
    "│",
    "│ Deployed at:  \(.deployedAt)",
    "│ Started at:   \(.deployStartedAt // "-")",
    "│ Triggered by: \(if .initiatedBy.automated then "automated sync" else (.initiatedBy.username // "manual") end)",
    "├─────────────────────────────────────────────────",
    "│ Sources & Revisions:",
    (
      if .sources then
        (.sources | to_entries[] |
          "│   [\(.key + 1)] \(.value.repoURL)",
          "│       chart=\(.value.chart // "-")  path=\(.value.path // "-")  target=\(.value.targetRevision // "-")"
        )
      elif .source.repoURL then
        "│   [1] \(.source.repoURL)",
        "│       path=\(.source.path // "-")  target=\(.source.targetRevision // "-")"
      else
        "│   (no source info)"
      end
    ),
    "│",
    "│ Revisions:    \((.revisions // [.revision // "-"]) | join("  |  "))",
    "└─────────────────────────────────────────────────"
  '
}

# Helper: pick an env from logged-in sessions
pick_env() {
  local prompt="${1:-Select environment}" exclude="${2:-}"
  local logged_in_servers
  logged_in_servers=$(argocd context 2>/dev/null | awk 'NR>1 {print $NF}') || true

  if [[ -z "$logged_in_servers" ]]; then
    echo "No logged-in environments found. Run 'login' first." >&2
    return 1
  fi

  local fzf_input
  fzf_input=$(
    for entry in "${ENVS[@]}"; do
      local entry_label="${entry%%|*}"
      local entry_server="${entry##*|}"
      # Skip excluded server
      [[ "$entry_server" == "$exclude" ]] && continue
      if echo "$logged_in_servers" | grep -qx "$entry_server"; then
        printf "%-20s  %s\n" "$entry_label" "$entry_server"
      fi
    done
  )

  if [[ -z "$fzf_input" ]]; then
    echo "No logged-in environments found." >&2
    return 1
  fi

  local selection
  selection=$(echo "$fzf_input" | \
    fzf --height=10 --reverse \
        --prompt="$prompt > " \
        --header="Logged-in environments" \
  ) || return 1

  # Return "label|server"
  local sel_server sel_label=""
  sel_server=$(echo "$selection" | awk '{print $NF}')
  for entry in "${ENVS[@]}"; do
    local entry_server="${entry##*|}"
    if [[ "$entry_server" == "$sel_server" ]]; then
      sel_label="${entry%%|*}"
      break
    fi
  done
  echo "${sel_label}|${sel_server}"
}

pick_app_from_env() {
  local server="$1" label="$2" prompt="${3:-Select app}" query="${4:-}"

  echo "Fetching apps from $label ..." >&2
  local app_list
  app_list=$(argocd app list --argocd-context "$server" --grpc-web -o json 2>/dev/null) || {
    echo "Error: failed to fetch apps from $label." >&2
    return 1
  }

  local table
  table=$(echo "$app_list" | jq -r '
    .[] |
    [
      .metadata.name,
      .spec.project,
      .spec.destination.namespace,
      (.status.sync.status   // "-"),
      (.status.health.status // "-")
    ] | @tsv
  ' | sort | column -t -s $'\t')

  if [[ -z "$table" ]]; then
    echo "No apps found in $label." >&2
    return 1
  fi

  local count
  count=$(echo "$table" | wc -l | tr -d ' ')
  local header="NAME  PROJECT  NAMESPACE  SYNC  HEALTH  CONDITIONS"

  local fzf_args=(
    --header="$header  [$count app(s) in $label]"
    --reverse
    --height=80%
    --prompt="$prompt > "
  )
  [[ -n "$query" ]] && fzf_args+=(--query="$query")

  local selection
  selection=$(echo "$table" | fzf "${fzf_args[@]}") || return 1
  echo "$selection" | awk '{print $1}'
}

# Helper: extract a common suffix from an app name (strip env/cluster prefix)
# e.g. "beta-c9-eks-use1-wa-identity-ui" → "identity-ui"
app_name_suffix() {
  local name="$1"
  # Strip the common prefix pattern: env-c9-eks-region-cluster-type-
  # The service name typically comes after "wa-", "enc-", or similar markers
  echo "$name" | sed -E 's/^[a-z]+-c9-eks-[a-z0-9]+-[a-z]+-//' | sed -E 's/^[a-z]+-c9-eks-[a-z0-9]+-//'
}

cmd_compare() {
  local continuing=false
  if [[ "${1:-}" == "--continue" ]]; then
    continuing=true
  fi

  local env_a_label env_a_server env_b_label env_b_server
  local app_a app_b source

  if [[ "$continuing" == true ]] && has_last compare; then
    env_a_server="$(load_last compare env_a_server)"
    env_a_label="$(load_last compare env_a_label)"
    env_b_server="$(load_last compare env_b_server)"
    env_b_label="$(load_last compare env_b_label)"
    app_a="$(load_last compare app_a)"
    app_b="$(load_last compare app_b)"
    source="$(load_last compare source)"

    if [[ -n "$app_a" && -n "$app_b" && -n "$env_a_server" && -n "$env_b_server" && -n "$source" ]]; then
      echo "Continuing: $app_a ($env_a_label) vs $app_b ($env_b_label)  source=$source"
    else
      echo "No previous compare session found. Starting fresh."
      continuing=false
    fi
  fi

  if [[ "$continuing" == false ]]; then
    # guard: need at least 2 logged-in envs
    local session_count
    session_count=$(argocd context 2>/dev/null | awk 'NR>1' | wc -l | tr -d ' ') || true
    if (( session_count < 2 )); then
      echo "Compare needs at least 2 logged-in environments (found $session_count)."
      echo "Run 'login' to add more sessions."
      return 1
    fi

    # Step 1: pick two environments
    echo "Pick the first environment:"
    local env_a
    env_a=$(pick_env "Env A") || return 0
    env_a_label="${env_a%%|*}"
    env_a_server="${env_a##*|}"

    echo ""
    echo "Pick the second environment:"
    local env_b
    env_b=$(pick_env "Env B" "$env_a_server") || return 0
    env_b_label="${env_b%%|*}"
    env_b_server="${env_b##*|}"

    echo ""

    # Step 2: pick app in env A
    app_a=$(pick_app_from_env "$env_a_server" "$env_a_label" "Select app in $env_a_label") || return 0

    # Step 3: pick app in env B, pre-populated with common suffix
    local hint
    hint=$(app_name_suffix "$app_a")
    echo ""
    app_b=$(pick_app_from_env "$env_b_server" "$env_b_label" "Select app in $env_b_label" "$hint") || return 0

    # Step 4: pick source
    echo ""
    source=$(printf 'live  (what is running in the cluster)\ngit   (desired state from repo)' | \
      fzf --height=6 --reverse \
          --prompt="Manifest source > " \
          --header="Compare using which source?" \
    ) || return 0
    source=$(echo "$source" | awk '{print $1}')

    save_last compare \
      env_a_server "$env_a_server" \
      env_a_label "$env_a_label" \
      env_b_server "$env_b_server" \
      env_b_label "$env_b_label" \
      app_a "$app_a" \
      app_b "$app_b" \
      source "$source"
  fi

  # Step 5: fetch manifests from both envs
  echo ""
  echo "Fetching $source manifests..."
  echo "  A: $app_a ($env_a_label)"
  echo "  B: $app_b ($env_b_label)"

  local manifests_a manifests_b
  manifests_a=$(argocd app manifests "$app_a" --argocd-context "$env_a_server" --grpc-web --source "$source" 2>/dev/null) || true
  manifests_b=$(argocd app manifests "$app_b" --argocd-context "$env_b_server" --grpc-web --source "$source" 2>/dev/null) || true

  if [[ -z "$manifests_a" ]]; then
    echo "Error: no manifests returned for $app_a" >&2
    return 1
  fi
  if [[ -z "$manifests_b" ]]; then
    echo "Error: no manifests returned for $app_b" >&2
    return 1
  fi

  # Step 6: build resource index from env A, let user pick or diff all
  local index_a
  index_a=$(echo "$manifests_a" | awk '
    BEGIN { doc=0; kind=""; name=""; ns="" }
    /^---/ { if (kind != "") printf "%d\t%s/%s\t%s\n", doc, kind, name, ns; doc++; kind=""; name=""; ns="" }
    /^kind:/ { kind=$2 }
    /^  name:/ && name == "" { name=$2 }
    /^  namespace:/ { ns=$2 }
    END { if (kind != "") printf "%d\t%s/%s\t%s\n", doc, kind, name, ns }
  ')

  local res_count
  res_count=$(echo "$index_a" | wc -l | tr -d ' ')

  local pick_list
  pick_list=$(
    echo "[ALL]  Diff all manifests"
    echo "$index_a" | awk -F'\t' '{printf "%-40s  ns=%s\n", $2, ($3 == "" ? "-" : $3)}'
  )

  echo ""
  local selection
  selection=$(echo "$pick_list" | \
    fzf --height=60% --reverse \
        --prompt="Pick resource to compare > " \
        --header="$res_count resource(s) — comparing $env_a_label vs $env_b_label" \
  ) || return 0

  echo ""

  if echo "$selection" | grep -q '^\[ALL\]'; then
    echo "── Diff ALL: $app_a ($env_a_label) vs $app_b ($env_b_label) ──"
    echo ""
    local tmp_a tmp_b
    tmp_a=$(_mktmp)
    tmp_b=$(_mktmp)

    echo "$manifests_a" > "$tmp_a"
    echo "$manifests_b" > "$tmp_b"

    show_diff "$tmp_a" "$tmp_b" "$app_a ($env_a_label)" "$app_b ($env_b_label)"
  else
    # Extract the selected kind/name
    local selected_kind_name
    selected_kind_name=$(echo "$selection" | awk '{print $1}')
    local sel_kind sel_name
    sel_kind="${selected_kind_name%%/*}"
    sel_name="${selected_kind_name#*/}"

    echo "── Diff $selected_kind_name: $env_a_label vs $env_b_label ──"
    echo ""

    # Extract matching doc from each manifest stream by kind
    local doc_a doc_b
    doc_a=$(echo "$manifests_a" | awk -v target_kind="$sel_kind" -v target_name="$sel_name" '
      BEGIN { doc=""; kind=""; mname=""; found=0 }
      /^---/ {
        if (kind == target_kind && mname == target_name) { found=1; print doc; exit }
        doc=""; kind=""; mname=""; next
      }
      { doc = (doc == "" ? $0 : doc "\n" $0) }
      /^kind:/ { kind=$2 }
      /^  name:/ && mname == "" { mname=$2 }
      END { if (!found && kind == target_kind && mname == target_name) print doc }
    ')

    doc_b=$(echo "$manifests_b" | awk -v target_kind="$sel_kind" -v target_name="$sel_name" '
      BEGIN { doc=""; kind=""; mname=""; found=0 }
      /^---/ {
        if (kind == target_kind && mname == target_name) { found=1; print doc; exit }
        doc=""; kind=""; mname=""; next
      }
      { doc = (doc == "" ? $0 : doc "\n" $0) }
      /^kind:/ { kind=$2 }
      /^  name:/ && mname == "" { mname=$2 }
      END { if (!found && kind == target_kind && mname == target_name) print doc }
    ')

    if [[ -z "$doc_a" && -z "$doc_b" ]]; then
      echo "Resource $selected_kind_name not found in either environment."
      return 1
    fi

    local tmp_a tmp_b
    tmp_a=$(_mktmp)
    tmp_b=$(_mktmp)

    echo "${doc_a:-# (not found in $env_a_label)}" > "$tmp_a"
    echo "${doc_b:-# (not found in $env_b_label)}" > "$tmp_b"

    show_diff "$tmp_a" "$tmp_b" "$app_a ($env_a_label)" "$app_b ($env_b_label)"
  fi
}

usage() {
  cat <<EOF
argoq v2 - quick ArgoCD lookup tool

Usage: $(basename "$0") <command> [flags]

Commands:
  login              Select an environment and login via SSO
  logout             Logout from the current environment
  logout --all       Logout from all environments
  apps               List and search applications (cached, fzf)
  apps --live        Bypass cache and fetch fresh app list
  apps --unhealthy   Show only unhealthy/unsynced/errored apps
  open               Open an app in the ArgoCD UI (browser)
  logs               View/stream logs (app-wide, namespace, resource, container)
  manifests          View app manifests (live/git)
  resources          Drill into an app's resources (live/git/diff)
  history            Show deployment history for an app
  compare            Diff manifests for same app across two envs
  whoami             Show session, user, cache, and env info

Flags:
  --continue         Re-use previous selections (all commands)
  --live             Force fresh API fetch (apps)
  --unhealthy        Filter to troubled apps only (apps)

Environment:
  ARGOQ_DIFF         Override diff viewer (highest priority)
                     e.g. ARGOQ_DIFF=code argoq compare

Optional tools (auto-detected, graceful fallbacks):
  nvim / vim         Preferred diff viewer (side-by-side, readonly)
  \$EDITOR            Honoured if set (vim, code, cursor, etc.)
  code / cursor      Used for --diff if no terminal editor found
  bat                YAML syntax highlighting (falls back to cat)

Notes:
  · Selecting an app in 'apps' opens an action menu to flow
    directly into logs, manifests, resources, history, or open.
  · App picker remembers your last selection across commands.
  · Diff priority: \$ARGOQ_DIFF → nvim → \$EDITOR → code/cursor → diff+bat → diff+cat

EOF
}

# Entry point
main() {
  check_deps

  local cmd="${1:-}"

  case "$cmd" in
    login)              cmd_login ;;
    logout)             shift; if [[ "${1:-}" == "--all" ]]; then cmd_logout_all; else cmd_logout; fi ;;
    apps)               shift; cmd_apps "$@" ;;
    open)               shift; cmd_open "$@" ;;
    logs)               shift; cmd_logs "$@" ;;
    manifests)          shift; cmd_manifests "$@" ;;
    resources)          shift; cmd_resources "$@" ;;
    history)            shift; cmd_history "$@" ;;
    compare)            shift; cmd_compare "$@" ;;
    whoami)             cmd_whoami ;;
    help|--help|-h)     usage ;;
    "")                 cmd_apps ;;
    *)                  echo "Unknown command: $cmd -- see --help for usage" >&2; return 1 ;;
  esac
}

main "$@"
