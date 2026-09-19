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

if [[ -z "${EDITOR:-}" ]]; then
  if command -v nvim >/dev/null 2>&1; then EDITOR="$(command -v nvim)"; else EDITOR="vim"; fi
  export EDITOR
fi
export GIT_CONFIG_GLOBAL="$HOME/dotfiles/git/.gitconfig"
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

if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --use-on-cd)"
fi
if command -v pyenv >/dev/null 2>&1; then
  eval "$(pyenv init - zsh)"
fi

# Completions snapshot the final PATH, so compinit runs after all PATH edits.
autoload -Uz compinit && compinit -C

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

# The one load-bearing source: a relocated checkout without it has no
# loader at all, so fail loud here instead of mysterious missing functions.
if [[ -f ~/dotfiles/zsh/functions/source_if_exists.zsh ]]; then
  source ~/dotfiles/zsh/functions/source_if_exists.zsh
else
  echo "dotfiles: missing ~/dotfiles/zsh/functions/source_if_exists.zsh; skipping shell helpers" >&2
fi

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
# syntax-highlighting LAST per upstream docs. Each guarded so a fresh
# clone without these packages still starts a working shell.
if command -v brew >/dev/null 2>&1; then
  _brew_prefix="$(brew --prefix)"
  [[ -f "$_brew_prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && \
    source "$_brew_prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
  [[ -f "$_brew_prefix/opt/zsh-vi-mode/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh" ]] && \
    source "$_brew_prefix/opt/zsh-vi-mode/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh"
  # Prefer the brew prefix (works on Intel too); keep the Apple-Silicon
  # default path as fallback for hand-installed highlighting.
  for _shl_syntax in "$_brew_prefix/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
                     /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
    if [[ -f "$_shl_syntax" ]]; then source "$_shl_syntax"; break; fi
  done
  unset _brew_prefix _shl_syntax
else
  # No brew: still try the well-known default location.
  [[ -f /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
    source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
# eval "$(gh copilot alias -- zsh)"

# tabtab source for packages
# uninstall by removing these lines
[[ -f ~/.config/tabtab/__tabtab.zsh ]] && . ~/.config/tabtab/__tabtab.zsh || true

# kubectl completion, cached: regenerates when older than ~48h (BSD find
# -mtime +1 means >48h, not 24h) so every shell start does not pay a
# synchronous subshell.
if (( $+commands[kubectl] )); then
  _kubectl_cache="$HOME/.cache/zsh/kubectl-completion.zsh"
  if [[ ! -f "$_kubectl_cache" ]] || [[ -n $(find "$_kubectl_cache" -mtime +1 2>/dev/null) ]]; then
    mkdir -p "${HOME}/.cache/zsh"
    _kubectl_tmp="$_kubectl_cache.tmp.$$"
    # Only move into place on success: a failed completion must never
    # poison the cache with an empty file for the next ~48h.
    if kubectl completion zsh >| "$_kubectl_tmp" 2>/dev/null && [[ -s "$_kubectl_tmp" ]]; then
      mv -f "$_kubectl_tmp" "$_kubectl_cache"
    else
      rm -f "$_kubectl_tmp"
    fi
    unset _kubectl_tmp
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
