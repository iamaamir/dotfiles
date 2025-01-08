#!/bin/bash

# Get a list of available sessions

tmux display-message "getting sessions"
sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null)

chosen_session=$(tmux choose-tree -N -F '#{session_name}' -P "Switch to session:")

if [ -n "$chosen_session" ]; then
  tmux switch-client -n -t "$chosen_session"
fi

tmux display-message "chosen session"
