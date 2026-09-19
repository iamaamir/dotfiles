# ~/.zsh/prompt.zsh
# Opt-in alternative prompt (cat emoji status). NOT sourced by default —
# starship is the chosen prompt (see .config/starship.toml).
# To try it: ENABLE_CAT_PROMPT=true source ~/dotfiles/zsh/prompt.zsh
# (this shadows the starship PROMPT for the current shell only).
if [[ -z "${ENABLE_CAT_PROMPT:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi

# PROMPT contains ${...} expansions — without this they render literally.
setopt prompt_subst

autoload -Uz add-zsh-hook vcs_info 2>/dev/null || true

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
# add-zsh-hook is autoloaded above; vcs_info for the Git segment.
zstyle ':vcs_info:git:*' formats ' %b'

# Add our custom functions to Zsh's hook chains.
# ORDER MATTERS: the status hook runs FIRST so `local exit_status=$?`
# still sees the real command status. vcs_info runs after (its own
# exit 0 would otherwise mask failures as success).
add-zsh-hook precmd precmd_set_status_emoji
add-zsh-hook precmd vcs_info
add-zsh-hook preexec preexec_capture_command
add-zsh-hook preexec preexec_sudo_indicator

# --- Final Prompt Definition ---
# This defines how your prompt will look.
# It uses the global variables set by the hook functions.

PROMPT='%F{#7DFFFF}%~%f${vcs_info_msg_0_}${_MY_SUDO_PROMPT_INDICATOR}
${_MY_PROMPT_STATUS_SYMBOL} %f'