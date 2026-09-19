# ~/.zsh/prompt.zsh
# This file contains custom Zsh prompt logic for dynamic emoji switching.

# --- Global Variables ---
# These variables store information needed across different prompt functions.
LAST_COMMAND_NAME=""          # Stores the name of the command that just executed.
_MY_PROMPT_STATUS_SYMBOL=""   # Stores the emoji and color for the prompt's status.
_MY_SUDO_PROMPT_INDICATOR="" # Stores the emoji and color for sudo command detection.

# --- Hook Functions ---
# These functions are called by Zsh at specific points in the command lifecycle.

# preexec_capture_command: Captures the command name *before* execution.
# This allows us to check for 'cat' or 'sudo'.
preexec_capture_command() {
  # $1 is the full command line about to be executed.
  # ${1%% *} extracts everything before the first space, which is the command name.
  LAST_COMMAND_NAME="${1%% *}"
}

# preexec_sudo_indicator: Sets a special indicator if the command starts with 'sudo'.
# This indicator will show *before* the command executes.
preexec_sudo_indicator() {
  local command_line="$1" # Get the full command line.
  if [[ "$command_line" == sudo* ]]; then
    # If the command starts with 'sudo', show the big smiling cat.
    _MY_SUDO_PROMPT_INDICATOR="%F{#FFA500}😸%f " # Orange big smiling cat
  else
    # Otherwise, clear the indicator.
    _MY_SUDO_PROMPT_INDICATOR=""
  fi
}

# precmd_set_status_emoji: Determines the status emoji *after* a command executes.
# This function is called before the prompt is displayed.
precmd_set_status_emoji() {
  local exit_status=$? # Get the exit status of the previously run command.
  local prompt_symbol_string="" # Temporary variable to build the emoji string.

  if [[ "$exit_status" -eq 0 ]]; then
    # Command was successful (exit status is 0).
    if [[ "$LAST_COMMAND_NAME" == "cat" ]]; then
      # Special case: Successful 'cat' command.
      prompt_symbol_string="%F{#e655b5}😻" # Heart eyes cat (pink/magenta)
    else
      # Any other successful command.
      prompt_symbol_string="%F{#e655b5}😺" # Normal grinning cat (pink/magenta)
    fi
  else
    # Command failed (exit status is non-zero).
    prompt_symbol_string="%F{red}😿" # Crying cat (red)
  fi

  # Store the determined emoji string (including color) in the global variable
  # that the main PROMPT will use.
  _MY_PROMPT_STATUS_SYMBOL="$prompt_symbol_string"

  # Reset LAST_COMMAND_NAME for the next command cycle to prevent incorrect
  # emoji display if no command is run immediately after.
  LAST_COMMAND_NAME=""
}

# --- Hook Registration ---
# Ensure 'autoload -Uz add-zsh-hook' is run *before* these calls.
# We'll put add-zsh-hook in .zshrc, then add these specific functions to the hooks.

# Add our custom functions to Zsh's hook chains.
add-zsh-hook preexec preexec_capture_command
add-zsh-hook preexec preexec_sudo_indicator
add-zsh-hook precmd precmd_set_status_emoji
# Note: precmd_vcs_info (for Git status) is already added in your main .zshrc.
# It's important that precmd_set_status_emoji runs *after* any command has completed
# and its exit status is known, which it naturally does in the precmd chain.

# --- Final Prompt Definition ---
# This defines how your prompt will look.
# It uses the global variables set by the hook functions.

						
PROMPT='%F{#7DFFFF}%~%f${vcs_info_msg_0_}${_MY_SUDO_PROMPT_INDICATOR}
${_MY_PROMPT_STATUS_SYMBOL} %f'