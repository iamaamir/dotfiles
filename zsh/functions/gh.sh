#!/bin/bash
# Sourced into zsh via .zshrc (gh PR helpers). Keep syntax POSIX/zsh-compatible.

# ANSI color codes
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
BOLD="\e[1m"
RESET="\e[0m"

DEFAULT_ASSIGNEE="@me"

pr() {
  # Check if the current directory is a valid Git repository
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo -e "${RED}${BOLD}❌ Not in a valid Git repository. Operation canceled. ❌${RESET}"
    return 1
  fi

  # Use 'git branch' to list all local branches
  branches=$(git branch | awk '{print $NF}')

  # Use 'fzf' to interactively select a branch with a custom title
  base_branch=$(echo "$branches" | fzf --height=20% --reverse --header="🌱 Select the base branch:")

  # Ensure the user has selected a branch
  if [[ -z "$base_branch" ]]; then
    echo -e "${RED}${BOLD}❌ No branch selected. Operation canceled. ❌${RESET}"
    return 1
  fi

  # Confirm the user's choice
  echo -e "${GREEN}🌱 Base Branch:${RESET} (${BOLD}$base_branch${RESET})"

  # Ask for confirmation
  echo -e "${YELLOW}${BOLD}🚀 Create this PR as a draft? (y/n)${RESET}"
  read -r confirmation

  if [[ "$confirmation" =~ ^[Yy]$ ]]; then
    # Run the 'gh pr create' command to create the PR with the "draft" state
    gh pr create --base "$base_branch" --assignee "$DEFAULT_ASSIGNEE" --draft

    if [ $? -eq 0 ]; then
      echo -e "${GREEN}${BOLD}✅ Pull Request created successfully! 🎉${RESET}"
    else
      echo -e "${RED}${BOLD}❌ Error creating the Pull Request. Please try again. ❌${RESET}"
    fi
  else
    echo -e "${RED}${BOLD}🚫 Operation canceled. No PR created. 🚫${RESET}"
  fi
}

# Call the function
#pr

