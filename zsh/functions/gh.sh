#!/bin/bash
# Sourced into zsh via .zshrc. zsh/bash syntax only (uses [[ ]], (( )), local -a).

# ANSI color codes
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
BOLD="\e[1m"
RESET="\e[0m"

DEFAULT_ASSIGNEE="@me"

pr_usage() {
  cat <<EOF
Usage: pr [OPTIONS]

Create a GitHub PR for the current branch (draft by default).

Options:
  --base BRANCH      Base branch (skips the fzf picker; required without a TTY).
                     Remote-only bases must be qualified: origin/<branch>.
  --title TITLE      PR title (skips gh's interactive title prompt)
  --body BODY        PR body (skips gh's interactive body prompt)
                     (values starting with - need the --opt=value form)
  --assignee USER    Assignee (default: $DEFAULT_ASSIGNEE)
  --head BRANCH      Head branch (default: current branch)
  --draft            Create as draft (default)
  --no-draft         Create as ready-for-review
  --dry-run          Print what gh would do without creating the PR
  -y, --yes          Skip the confirmation prompt (required without a TTY)
  -h, --help         Show this help

Examples:
  pr                                        # fully interactive
  pr --base main -y --title "Fix login"     # scriptable (agents, hooks)
  pr --base main --no-draft --dry-run       # preview without side effects
EOF
}

pr() {
  local base_branch="" title="" body="" assignee="$DEFAULT_ASSIGNEE" head=""
  local draft=true dry_run=false assume_yes=false

  # Parse flags (everything else is rejected so typos fail loudly).
  # Value flags need an explicit arity check: "${2:?…}" alone prints the
  # shell's own error AND falls through to shift 2, double-reporting.
  local needs_value
  while (( $# )); do
    # Split --opt=value form first so dash-leading values keep working.
    local opt="$1" val=""
    case "$opt" in
      --*=*) val="${opt#*=}"; opt="${opt%%=*}" ;;
    esac
    case "$opt" in
      --base|--title|--body|--assignee|--head)
        needs_value="$opt"
        if [[ -n "$val" ]]; then
          : # value came from --opt=value
        elif (( $# >= 2 )) && [[ "$2" != -* ]]; then
          val="$2"; shift
        else
          echo -e "${RED}${BOLD}❌ $needs_value requires a value (see pr --help) ❌${RESET}"
          return 2
        fi
        case "$needs_value" in
          --base)     base_branch="$val" ;;
          --title)    title="$val" ;;
          --body)     body="$val" ;;
          --assignee) assignee="$val" ;;
          --head)     head="$val" ;;
        esac
        shift ;;
      --draft)    draft=true; shift ;;
      --no-draft) draft=false; shift ;;
      --dry-run)  dry_run=true; shift ;;
      -y|--yes)   assume_yes=true; shift ;;
      -h|--help)  pr_usage; return 0 ;;
      --)         shift; break ;;
      -*)         echo -e "${RED}${BOLD}❌ Unknown option: $1 (see pr --help) ❌${RESET}"; return 2 ;;
      *)          echo -e "${RED}${BOLD}❌ Unexpected argument: $1 (see pr --help) ❌${RESET}"; return 2 ;;
    esac
  done

  # Anything left after `--` is a caller error, not something to ignore.
  if (( $# )); then
    echo -e "${RED}${BOLD}❌ Unexpected argument(s) after --: $* (see pr --help) ❌${RESET}"
    return 2
  fi

  # Check if the current directory is a valid Git repository
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo -e "${RED}${BOLD}❌ Not in a valid Git repository. Operation canceled. ❌${RESET}"
    return 1
  fi

  # Base branch: explicit flag wins (agents, pipes); otherwise fzf needs a TTY.
  # Accept local branches and anything resolving to a commit (remote
  # branches, tags), since fresh clones may not have the base locally.
  if [[ -n "$base_branch" ]]; then
    if ! git rev-parse --verify --quiet "$base_branch^{commit}" >/dev/null; then
      echo -e "${RED}${BOLD}❌ Unknown base ref: $base_branch ❌${RESET}"
      return 1
    fi
  else
    if [[ ! -t 0 ]]; then
      echo -e "${RED}${BOLD}❌ No TTY for the branch picker. Re-run with --base BRANCH. ❌${RESET}"
      return 1
    fi
    if ! command -v fzf >/dev/null 2>&1; then
      echo -e "${RED}${BOLD}❌ fzf is required for branch selection (or pass --base). ❌${RESET}"
      return 1
    fi
    # Use 'git branch' to list all local branches
    local branches
    branches=$(git branch | awk '{print $NF}')

    # Use 'fzf' to interactively select a branch with a custom title
    base_branch=$(echo "$branches" | fzf --height=20% --reverse --header="🌱 Select the base branch:")

    # Ensure the user has selected a branch
    if [[ -z "$base_branch" ]]; then
      echo -e "${RED}${BOLD}❌ No branch selected. Operation canceled. ❌${RESET}"
      return 1
    fi
  fi

  # Confirm the user's choice
  echo -e "${GREEN}🌱 Base Branch:${RESET} (${BOLD}$base_branch${RESET})"

  if [[ "$assume_yes" != true ]]; then
    if [[ ! -t 0 ]]; then
      echo -e "${RED}${BOLD}❌ No TTY for confirmation. Re-run with --yes. ❌${RESET}"
      return 1
    fi
    # Ask for confirmation
    echo -e "${YELLOW}${BOLD}🚀 Create this PR as a draft? (y/n)${RESET}"
    local confirmation
    read -r confirmation

    if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
      echo -e "${RED}${BOLD}🚫 Operation canceled. No PR created. 🚫${RESET}"
      return 0
    fi
  fi

  # Assemble the gh invocation; --title/--body only when given so humans
  # still get gh's interactive prompts when they omit them
  local -a gh_args=(pr create --base "$base_branch" --assignee "$assignee")
  [[ "$draft" == true ]] && gh_args+=(--draft)
  [[ -n "$head" ]] && gh_args+=(--head "$head")
  [[ -n "$title" ]] && gh_args+=(--title "$title")
  [[ -n "$body" ]] && gh_args+=(--body "$body")
  [[ "$dry_run" == true ]] && gh_args+=(--dry-run)

  # Run the 'gh pr create' command to create the PR
  if gh "${gh_args[@]}"; then
    if [[ "$dry_run" == true ]]; then
      echo -e "${GREEN}${BOLD}✅ Dry run OK — no PR created. 🎉${RESET}"
    else
      echo -e "${GREEN}${BOLD}✅ Pull Request created successfully! 🎉${RESET}"
    fi
  else
    echo -e "${RED}${BOLD}❌ Error creating the Pull Request. Please try again. ❌${RESET}"
    return 1
  fi
}

# Call the function
#pr

