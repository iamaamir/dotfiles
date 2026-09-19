# Prompt: starship is the chosen prompt (see .config/starship.toml).
# zsh/prompt.zsh is a legacy/opt-in alternative, not sourced by default.
ZVM_VI_ESCAPE_BINDKEY=jk
ZVM_VI_INSERT_ESCAPE_BINDKEY=jk
autoload -Uz add-zsh-hook

# WezTerm Shell Integration
if [[ -n "$WEZTERM_PANE" ]]; then
  [[ -f "$WEZTERM_EXECUTABLE_DIR/../Resources/wezterm.sh" ]] && \
    source "$WEZTERM_EXECUTABLE_DIR/../Resources/wezterm.sh"
fi

export EDITOR="/opt/homebrew/bin/nvim"
export GIT_CONFIG_GLOBAL=$HOME/dotfiles/git/.gitconfig
export BAT_THEME="gruvbox-dark"

# --- PATH assembly (one place; first writer wins, no duplicates) ---
path_prepend() {
  [[ -d "$1" ]] || return 0
  case ":$PATH:" in
    *":$1:"*) ;;
    *) PATH="$1:$PATH" ;;
  esac
}
path_append() {
  [[ -d "$1" ]] || return 0
  case ":$PATH:" in
    *":$1:"*) ;;
    *) PATH="$PATH:$1" ;;
  esac
}
export PYENV_ROOT="$HOME/.pyenv"
path_prepend "$PYENV_ROOT/bin"
# Pinned fnm node (was hardcoded to /Users/mak; $HOME keeps it portable)
path_prepend "$HOME/.local/share/fnm/node-versions/v24.14.0/installation/bin"
export BUN_INSTALL="$HOME/.bun"
path_prepend "$BUN_INSTALL/bin"
path_append "$HOME/.lmstudio/bin"  # Added by LM Studio CLI (lms)
path_prepend "$HOME/.kimi-code/bin"  # kimi-code
[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"

eval "$(fnm env --use-on-cd)"
eval "$(pyenv init - zsh)"

# Completions snapshot the final PATH, so compinit runs after all PATH edits.
autoload -Uz compinit && compinit -C

eval "$(starship init zsh)"

source ~/dotfiles/zsh/functions/source_if_exists.zsh

files_to_source=(
    ~/dotfiles/zsh/privatealiases.zsh
    ~/dotfiles/zsh/.aliases
    ~/.fzf.zsh
    /opt/homebrew/etc/profile.d/autojump.sh
   ~/dotfiles/zsh/functions/gh.sh
   ~/dotfiles/zsh/functions/openprs.sh
)
source_if_exists "${files_to_source[@]}"

#test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

# Highlighting stack order matters: autosuggestions, vi-mode, then
# syntax-highlighting LAST per upstream docs.
source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source $(brew --prefix)/opt/zsh-vi-mode/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
# eval "$(gh copilot alias -- zsh)"

# tabtab source for packages
# uninstall by removing these lines
[[ -f ~/.config/tabtab/__tabtab.zsh ]] && . ~/.config/tabtab/__tabtab.zsh || true

# kubectl completion, cached: regenerates at most once per day so every
# shell start does not pay a synchronous subshell.
if (( $+commands[kubectl] )); then
  _kubectl_cache="$HOME/.cache/zsh/kubectl-completion.zsh"
  if [[ ! -f "$_kubectl_cache" ]] || [[ -n $(find "$_kubectl_cache" -mtime +1 2>/dev/null) ]]; then
    mkdir -p "${HOME}/.cache/zsh"
    kubectl completion zsh >| "$_kubectl_cache" 2>/dev/null || true
  fi
  [[ -f "$_kubectl_cache" ]] && source "$_kubectl_cache"
  unset _kubectl_cache
fi

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# Announce directory changes without shadowing WezTerm's own chpwd hook
# (only one chpwd() function can exist; hooks chain instead).
my_chpwd_announce() {
  echo "Now in: $PWD"
  ls
}
add-zsh-hook chpwd my_chpwd_announce
