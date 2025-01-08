#!/bin/bash

get_git_branch() {
    local branch
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        branch=$(git symbolic-ref --short HEAD 2>&1)
        echo "$branch"
    else
        echo ""
    fi
}

clock() {
		date "+%a %e %b %-I:%M %p"
}

no_branch_status(){
  echo "#[fg=colour072]Session(#[fg=colour35]#S#[fg=colour072]) #[fg=colour072]| #[fg=colour067,bold]$(clock)#[default]"
}

current_dir="$(tmux display-message -p "#{pane_current_path}")"
cd "$current_dir" || exit 1

if [ "$(tmux display-message -p "#{pane_current_command}")" = "vim" ]; then
    git_branch=$(get_git_branch)
    if [ -n "$git_branch" ]; then
      echo "#[fg=colour072]Session(#[fg=colour35]#S#[fg=colour072]) #[fg=colour223]  $git_branch  #[default]"
    else
				no_branch_status
    fi
else
    # Echo the current session along with the ASCII clock
    no_branch_status
fi

