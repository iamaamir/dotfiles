# WezTerm Shell Integration for Zsh
# Source this file in your .zshrc: source ~/.config/wezterm-config/shell-integration.zsh
#
# This enables:
# - User variable support (show git branch, project name in tab titles)
# - OSC 7 for current working directory tracking
# - Custom escape sequences for WezTerm features

# Check if running in WezTerm
if [[ -z "$WEZTERM_PANE" ]]; then
    return
fi

# ============================================================================
# USER VARIABLE HELPER
# ============================================================================
# Sets a user variable that WezTerm can read via pane:get_user_vars()
__wezterm_set_user_var() {
    if hash base64 2>/dev/null; then
        printf "\033]1337;SetUserVar=%s=%s\007" "$1" "$(echo -n "$2" | base64)"
    fi
}

# ============================================================================
# GIT BRANCH IN TAB TITLE
# ============================================================================
# Updates the GIT_BRANCH user var when changing directories
__wezterm_update_git_branch() {
    local branch=""
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        branch=$(git symbolic-ref --short HEAD 2>/dev/null || git describe --tags --exact-match 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    fi
    __wezterm_set_user_var "GIT_BRANCH" "$branch"
}

# ============================================================================
# PROJECT NAME DETECTION
# ============================================================================
# Sets PROJECT_NAME based on common project indicators
__wezterm_update_project() {
    local project=""
    
    # Check for package.json (Node.js)
    if [[ -f "package.json" ]]; then
        project=$(grep -m1 '"name"' package.json | cut -d'"' -f4)
    # Check for Cargo.toml (Rust)
    elif [[ -f "Cargo.toml" ]]; then
        project=$(grep -m1 '^name' Cargo.toml | cut -d'"' -f2)
    # Check for pyproject.toml (Python)
    elif [[ -f "pyproject.toml" ]]; then
        project=$(grep -m1 '^name' pyproject.toml | cut -d'"' -f2)
    # Check for go.mod (Go)
    elif [[ -f "go.mod" ]]; then
        project=$(head -1 go.mod | awk '{print $2}' | sed 's|.*/||')
    fi
    
    __wezterm_set_user_var "PROJECT_NAME" "$project"
}

# ============================================================================
# COMMAND TRACKING
# ============================================================================
# Set WEZTERM_PROG to track what command is running
__wezterm_track_command() {
    local cmd="$1"
    # Only track significant commands
    case "$cmd" in
        vim*|nvim*|nano*|emacs*)
            __wezterm_set_user_var "WEZTERM_PROG" "$(echo $cmd | awk '{print $1}')"
            ;;
        ssh*|docker*|kubectl*)
            __wezterm_set_user_var "WEZTERM_PROG" "$(echo $cmd | awk '{print $1}')"
            ;;
        *)
            __wezterm_set_user_var "WEZTERM_PROG" ""
            ;;
    esac
}

# Clear command tracking when command finishes
__wezterm_clear_command() {
    __wezterm_set_user_var "WEZTERM_PROG" ""
}

# ============================================================================
# HOOKS
# ============================================================================
# Update user vars on directory change
__wezterm_chpwd() {
    __wezterm_update_git_branch
    __wezterm_update_project
}

# Add hooks
autoload -Uz add-zsh-hook
add-zsh-hook chpwd __wezterm_chpwd
add-zsh-hook preexec __wezterm_track_command
add-zsh-hook precmd __wezterm_clear_command

# Run once on shell startup
__wezterm_chpwd

# ============================================================================
# OSC 7 - CURRENT WORKING DIRECTORY
# ============================================================================
# This helps WezTerm know your current directory for new splits/tabs
__wezterm_osc7() {
    printf '\e]7;file://%s%s\e\\' "${HOST}" "${PWD}"
}

add-zsh-hook chpwd __wezterm_osc7
__wezterm_osc7

# ============================================================================
# HELPFUL ALIASES
# ============================================================================
# Quick alias to set a custom tab name
alias tabtitle='__wezterm_set_user_var PROJECT_NAME'

# Clear custom title
alias tabtitle-clear='__wezterm_set_user_var PROJECT_NAME ""'



