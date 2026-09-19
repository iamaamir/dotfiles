ZSH_THEME="eastwood"
ZVM_VI_ESCAPE_BINDKEY=jk
ZVM_VI_INSERT_ESCAPE_BINDKEY=jk
autoload -Uz compinit && compinit

# WezTerm Shell Integration
if [[ -n "$WEZTERM_PANE" ]]; then
  [[ -f "$WEZTERM_EXECUTABLE_DIR/../Resources/wezterm.sh" ]] && \
    source "$WEZTERM_EXECUTABLE_DIR/../Resources/wezterm.sh"
fi

export EDITOR="/opt/homebrew/bin/nvim"
export GIT_CONFIG_GLOBAL=$HOME/dotfiles/git/.gitconfig

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

# source <(kubectl completion zsh)
#test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

export BAT_THEME="gruvbox-dark"
eval "$(fnm env --use-on-cd)"
eval "$(starship init zsh)"

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - zsh)"

source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source $(brew --prefix)/opt/zsh-vi-mode/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh
# eval "$(gh copilot alias -- zsh)"

# tabtab source for packages
# uninstall by removing these lines
[[ -f ~/.config/tabtab/__tabtab.zsh ]] && . ~/.config/tabtab/__tabtab.zsh || true
[[ $commands[kubectl] ]] && source <(kubectl completion zsh) # add autocomplete permanently to your zsh shell

chpwd() {
  echo "Now in: $PWD"
  ls
}

. "$HOME/.local/bin/env"

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/mak/.lmstudio/bin"
# End of LM Studio CLI section


# Pi
export PATH="/Users/mak/.local/share/fnm/node-versions/v24.14.0/installation/bin:$PATH"

# bun completions
[ -s "/Users/mak/.bun/_bun" ] && source "/Users/mak/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# kimi-code
export PATH="/Users/mak/.kimi-code/bin:$PATH"
