vrg() (
    # Parse options
    literal=0

    case "${1:-}" in
        -F|--literal) literal=1; shift ;;
        -h|--help)
            echo "Usage: vrg [-F|--literal] PATTERN [PATH...]"
            return 0
            ;;
        --) shift ;;
    esac

    if [ "$#" -lt 1 ]; then
        echo "Usage: vrg [-F|--literal] PATTERN [PATH...]"
        return 2
    fi

    pattern=$1
    shift
    [ "$#" -gt 0 ] || set -- .

    # Excluded directories
    excludes=(
        .git node_modules .venv venv
        dist build coverage target
        .next __pycache__ vendor
    )

    # Editor fallback
    if command -v nvim >/dev/null 2>&1; then
        editor=nvim
    elif command -v vim >/dev/null 2>&1; then
        editor=vim
    elif command -v vi >/dev/null 2>&1; then
        editor=vi
    else
        echo "vrg: No editor available" >&2
        return 127
    fi

    # Temporary search results
    tmp=$(mktemp) || return 1
    trap 'rm -f -- "$tmp"' EXIT

    # Search: rg -> grep
    if command -v rg >/dev/null 2>&1; then
        opts=(--vimgrep)

        [ "$literal" -eq 1 ] && opts+=(--fixed-strings)

        for dir in "${excludes[@]}"; do
            opts+=(--glob "!**/$dir/**")
        done

        rg "${opts[@]}" -- "$pattern" "$@" > "$tmp"
        search_rc=$?

    elif command -v grep >/dev/null 2>&1; then
        opts=(-r -n -H -I)

        if [ "$literal" -eq 1 ]; then
            opts+=(-F)
        else
            opts+=(-E)
        fi

        for dir in "${excludes[@]}"; do
            opts+=(--exclude-dir="$dir")
        done

        grep "${opts[@]}" -- "$pattern" "$@" > "$tmp"
        search_rc=$?
    else
        echo "vrg: Neither rg nor grep available" >&2
        return 127
    fi

    case $search_rc in
        0) ;;
        1)
            echo "vrg: No matches for '$pattern'"
            return 1
            ;;
        *)
            echo "vrg: Search failed ($search_rc)" >&2
            return "$search_rc"
            ;;
    esac

    # Interactive selection with fzf
    use_fzf=0
    jump=1

    if command -v fzf >/dev/null 2>&1; then
        use_fzf=1

        selected=$(
            awk '{ print NR ":" $0 }' "$tmp" |
                fzf \
                    --height=80% \
                    --layout=reverse \
                    --border \
                    --delimiter=':' \
                    --with-nth='2..' \
                    --prompt='vrg > ' \
                    --header='Enter: open | Esc: cancel'
        )

        # Cancel without launching an editor
        [ -n "$selected" ] || return 0

        jump=${selected%%:*}
    fi

    # Open selected match
    case $editor in
        nvim)
            if [ "$use_fzf" -eq 1 ]; then
                nvim -q "$tmp" -c "${jump}cc"
            else
                nvim -q "$tmp" \
                    -c 'if exists(":Telescope") == 2 | Telescope quickfix | else | copen | endif'
            fi
            ;;

        vim)
            if [ "$use_fzf" -eq 1 ]; then
                vim -q "$tmp" -c "${jump}cc"
            else
                vim -q "$tmp" -c 'copen'
            fi
            ;;

        vi)
            selected_line=$(sed -n "${jump}p" "$tmp")
            file=${selected_line%%:*}
            rest=${selected_line#*:}
            line=${rest%%:*}

            vi "+${line}" "$file"
            ;;
    esac
)
