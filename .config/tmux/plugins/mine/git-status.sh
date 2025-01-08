#!/bin/bash

# Enable debugging
set -x

# Function to get the current Git branch
get_git_branch() {
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ -n "$branch" ]; then
        echo "Branch: $branch"
    fi
}

# Function to get the Git status
get_git_status() {
    status=$(git status --porcelain 2>/dev/null)
    if [ -n "$status" ]; then
        echo -e "Status:\n$status"
    fi
}

# Function to display Git status in a tmux popup
display_git_status() {
    pane_cwd=$(tmux display-message -p "#{pane_current_path}")
    echo "Current working directory: $pane_cwd"
    
    if cd "$pane_cwd"; then
        echo "Changed to directory: $(pwd)"

        branch=$(get_git_branch)
        status=$(get_git_status)

        if [ -n "$branch" ] || [ -n "$status" ]; then
            echo "Displaying Git status popup"
            tmux popup -E -w 80% -h 50% -x 10% -y 25% "Git Status:\n$branch\n$status" &
            
            # Wait for the user to press a key before continuing
            while : ; do
                read -n 1 -s -t 1 && break
            done

            # Close the popup after a key is pressed
            tmux popup -k
        fi
    else
        echo "Error: Could not change to directory: $pane_cwd"
    fi
}

# Call the function to display Git status
display_git_status

