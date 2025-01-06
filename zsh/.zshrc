ZSH_THEME="eastwood"
source ~/dotfiles/zsh/functions/source_if_exists.zsh

files_to_source=(
    ~/dotfiles/zsh/privatealiases.zsh
    ~/dotfiles/zsh/.aliases
    ~/.fzf.zsh
    /opt/homebrew/etc/profile.d/autojump.sh
    ~/dotfiles/zsh/functions/gh.sh
)
source_if_exists "${files_to_source[@]}"

source <(kubectl completion zsh)
#test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

export BAT_THEME="gruvbox-dark"
eval "$(fnm env --use-on-cd)"
eval "$(starship init zsh)"

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - zsh)"
