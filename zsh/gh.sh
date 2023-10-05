#!/bin/bash

# Configuration Options (set your defaults here)
DEFAULT_ASSIGNEE="@me"

pr() {
  # Use 'git branch' to list all local branches
  branches=$(git branch | awk '{print $NF}')

  # Use 'fzf' to interactively select a branch
  echo $'\e[32m🌱 Select the base branch:\e[0m'
  base_branch=$(echo "$branches" | fzf --height=20% --reverse)

  # Ensure the user has selected a branch
  if [[ -z "$base_branch" ]]; then
    echo $'\e[31m❌ No branch selected. Operation canceled. ❌\e[0m'
    exit 1
  fi

  # Confirm the user's choice
  echo $'\e[32m✅ Base Branch:\e[0m' "$base_branch"

  # Ask for confirmation
  read -p $'\e[32m🚀 Create this PR? (y/n): \e[0m' -r confirmation

  if [[ $confirmation =~ ^[Yy]$ ]]; then
    # Run the 'gh pr create' command to create the PR
    gh pr create --base "$base_branch" --assignee "$DEFAULT_ASSIGNEE"

    if [ $? -eq 0 ]; then
      echo $'\e[32m✅ Pull Request created successfully! 🎉\e[0m'
    else
      echo $'\e[31m❌ Error creating the Pull Request. Please try again. ❌\e[0m'
    fi
  else
    echo $'\e[31m🚫 Operation canceled. No PR created. 🚫\e[0m'
  fi
}

# Usage:
pr

