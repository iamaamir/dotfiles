# Source files if they exist. Missing OPTIONAL files (fzf, autojump) are
# silent; missing REQUIRED files (everything under ~/dotfiles) warn once.
source_if_exists() {
    local files=("$@")
    local failed_files=()

    for file_path in "${files[@]}"; do
        if [ -f "$file_path" ]; then
            if ! source "$file_path"; then
                failed_files+=("$file_path")
            fi
        else
            case "$file_path" in
                "$HOME/.fzf.zsh"|*/autojump.sh) ;;
                *) failed_files+=("$file_path") ;;
            esac
        fi
    done

    if [ ${#failed_files[@]} -gt 0 ]; then
        print "Failed to source files:"
        for file in "${failed_files[@]}"; do
            print "  - $file"
        done
    fi
}

