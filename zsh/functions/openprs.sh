#!/bin/bash
# Sourced into zsh via .zshrc (gh PR helpers). Keep syntax POSIX/zsh-compatible.
# Requires `gh` and `fzf`; the dependency guard lives inside showprs() so
# sourcing this file never kills the login shell.

# Default variables with the option to override via environment variables
# (OPENPRS_VERBOSE wins; legacy VERBOSE kept as fallback for compatibility)
github_user=${GITHUB_USER:-iamaamir}
pr_limit=${PR_LIMIT:-100}
verbose=${OPENPRS_VERBOSE:-${VERBOSE:-false}}

# Function to print verbose messages
log() {
    if [ "$verbose" = true ]; then
        echo -e "\033[34m$*\033[0m"
    fi
}

# Function to list PRs and perform actions
showprs() {
    if ! command -v gh &> /dev/null || ! command -v fzf &> /dev/null; then
        echo -e "\033[31m❌ gh and fzf are required but not installed. Please install them first.\033[0m"
        return 1
    fi
    log "GitHub user: $github_user"
    log "PR limit: $pr_limit"

    # List all PRs from the specified user and allow the user to select one
    selected_pr=$(gh search prs --author "$github_user" --state "open" --limit "$pr_limit" --json number,title,url,repository --jq '.[] | [.repository.nameWithOwner, .number, .title, .url] | @tsv' | fzf --delimiter='\t' --with-nth=1,3)

    # Check if any PR was selected
    if [ -z "$selected_pr" ]; then
        echo -e "\033[31m❌ No pull request selected.\033[0m"
        return 1
    fi

    # Extract the PR URL from the selected entry
    pr_url=$(echo "$selected_pr" | cut -f4)

    # Prompt the user for an action using fzf
    action=$(echo -e "Open in Browser 🌐\nCopy URL to Clipboard 📋\nDisplay PR Details 📝\nCancel 🚫" | fzf --prompt="Select an action: ")

    case $action in
        "Open in Browser 🌐")
            if [ -n "$pr_url" ]; then
                echo -e "\033[32m🌐 Opening PR in browser...\033[0m"
                gh pr view "$pr_url" --web
            else
                echo -e "\033[31m❌ Failed to extract the PR URL.\033[0m"
            fi
            ;;
        "Copy URL to Clipboard 📋")
            if [ -n "$pr_url" ]; then
                echo "$pr_url" | pbcopy
                echo -e "\033[32m📋 PR URL copied to clipboard.\033[0m"
            else
                echo -e "\033[31m❌ Failed to extract the PR URL.\033[0m"
            fi
            ;;
        "Display PR Details 📝")
            if [ -n "$pr_url" ]; then
                echo -e "\033[32m📝 Displaying PR details...\033[0m"
                gh pr view "$pr_url"
            else
                echo -e "\033[31m❌ Failed to extract the PR URL.\033[0m"
            fi
            ;;
        "Cancel 🚫")
            echo -e "\033[33m🚫 Action canceled.\033[0m"
            ;;
        *)
            echo -e "\033[31m❌ Invalid option.\033[0m"
            ;;
    esac
}

# Call the function
#showprs
