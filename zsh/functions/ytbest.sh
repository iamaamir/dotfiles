ytbest() {
  local url="$1"
  local base_dir="$2"
  local category="$3"

  local default_base_dir="$HOME/youtube-offline"

  # ------------------------------------------------------------
  # Usage
  #
  # Fully interactive:
  #
  #   ytbest
  #
  #   -> asks for URL
  #   -> asks for base directory (defaults to ~/youtube-offline)
  #   -> shows category picker
  #
  #
  # URL only:
  #
  #   ytbest URL
  #
  #   -> uses ~/youtube-offline
  #   -> shows category picker
  #
  #
  # URL + path:
  #
  #   ytbest URL PATH
  #
  #   -> uses PATH
  #   -> shows category picker
  #
  #
  # URL + path + category:
  #
  #   ytbest URL PATH CATEGORY
  #
  #   -> downloads directly into PATH/CATEGORY
  #
  #
  # Default path + explicit category:
  #
  #   ytbest URL - CATEGORY
  #
  #   -> downloads into ~/youtube-offline/CATEGORY
  # ------------------------------------------------------------


  # ------------------------------------------------------------
  # 1. Get the URL
  #
  # If no URL was supplied, ask for one.
  # Keep asking until the user provides something.
  # ------------------------------------------------------------

  while [[ -z "$url" ]]; do
    printf "YouTube URL: "
    read -r url

    # Trim whitespace.
    url="${url#"${url%%[![:space:]]*}"}"
    url="${url%"${url##*[![:space:]]}"}"

    if [[ -z "$url" ]]; then
      echo "A video URL is required."
      echo
    fi
  done


  # ------------------------------------------------------------
  # 2. Determine the base directory
  #
  # If ytbest was called completely interactively, ask for the base
  # directory as well. Pressing Enter accepts ~/youtube-offline.
  #
  # If a URL was supplied as an argument but no path was supplied,
  # keep the convenient existing behavior and automatically use the
  # default directory without asking.
  # ------------------------------------------------------------

  if (( $# == 0 )); then
    echo
    printf "Base directory [~/youtube-offline]: "
    read -r base_dir

    # Empty input means: use the default.
    if [[ -z "$base_dir" ]]; then
      base_dir="$default_base_dir"
    fi

  elif [[ -z "$base_dir" ]]; then
    base_dir="$default_base_dir"
  fi


  # "-" explicitly means: use the default directory.
  if [[ "$base_dir" == "-" ]]; then
    base_dir="$default_base_dir"
  fi


  # Expand ~/... supplied interactively or as an argument.
  base_dir="${base_dir/#\~/$HOME}"

  mkdir -p "$base_dir" || return 1


  # ------------------------------------------------------------
  # 3. Determine the category
  #
  # If one was explicitly supplied, trust it and skip fzf.
  #
  # Otherwise show existing directories and let the user:
  #
  #   - choose an existing category
  #   - create a new category
  #   - download directly into the base directory
  # ------------------------------------------------------------

  local output_dir

  if [[ -n "$category" ]]; then

    # Prevent accidental nested/escaping paths from being passed as
    # category names.
    if [[ "$category" == *"/"* ]]; then
      echo "Category name cannot contain '/'."
      return 1
    fi

    output_dir="$base_dir/$category"

  else

    # fzf powers the interactive category picker.
    if ! command -v fzf >/dev/null 2>&1; then
      echo "ytbest: fzf is required for interactive category selection."
      echo
      echo "Install it with:"
      echo "  brew install fzf"
      return 1
    fi


    local direct_option="[.] Download directly here"
    local create_option="[+] Create new category"

    local folders=()


    # ----------------------------------------------------------
    # Read immediate child directories only.
    #
    # Example:
    #
    #   ~/youtube-offline/
    #   ├── DSA/
    #   ├── golang/
    #   └── javascript/
    #
    # becomes:
    #
    #   DSA
    #   golang
    #   javascript
    # ----------------------------------------------------------

    while IFS= read -r folder; do
      [[ -n "$folder" ]] && folders+=("$folder")
    done < <(
      find "$base_dir" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -exec basename {} \; \
        2>/dev/null |
      sort -f
    )


    local selection


    # ----------------------------------------------------------
    # Show the category picker.
    #
    # Typing automatically fuzzy-searches your existing folders.
    # ----------------------------------------------------------

    selection="$(
      {
        printf '%s\n' "$direct_option"
        printf '%s\n' "$create_option"

        if (( ${#folders[@]} > 0 )); then
          printf '%s\n' "${folders[@]}"
        fi
      } |
      fzf \
        --prompt="Category > " \
        --height=50% \
        --layout=reverse \
        --border \
        --info=inline \
        --header="Choose where to save the video"
    )"


    # Esc or Ctrl-C cancels the operation.
    if [[ -z "$selection" ]]; then
      echo "Download cancelled."
      return 1
    fi


    case "$selection" in

      "$direct_option")

        output_dir="$base_dir"
        ;;


      "$create_option")

        local new_category=""

        echo

        # Keep asking until we receive a valid category name.
        while [[ -z "$new_category" ]]; do

          printf "New category: "
          read -r new_category

          # Trim whitespace.
          new_category="${new_category#"${new_category%%[![:space:]]*}"}"
          new_category="${new_category%"${new_category##*[![:space:]]}"}"

          if [[ -z "$new_category" ]]; then
            echo "Category name cannot be empty."
            continue
          fi

          # Keep categories as one directory level.
          if [[ "$new_category" == *"/"* ]]; then
            echo "Category name cannot contain '/'."
            new_category=""
          fi
        done

        category="$new_category"
        output_dir="$base_dir/$category"
        ;;


      *)

        category="$selection"
        output_dir="$base_dir/$category"
        ;;

    esac
  fi


  # ------------------------------------------------------------
  # 4. Create the destination if necessary.
  # ------------------------------------------------------------

  mkdir -p "$output_dir" || return 1


  # Show exactly where the video will go before downloading.
  echo
  echo "Destination: $output_dir"
  echo


  # ------------------------------------------------------------
  # 5. yt-dlp configuration
  # ------------------------------------------------------------

  local args=(

    # Pick the best available video stream plus the best available
    # audio stream. Fall back to the best combined stream if needed.
    -f "bv*+ba/b"


    # MKV supports modern codecs, subtitles, chapters, thumbnails,
    # and metadata without requiring a lossy re-encode.
    --merge-output-format mkv


    # Preserve useful video metadata.
    --embed-metadata


    # Preserve YouTube chapters when available.
    --embed-chapters


    # Embed the video thumbnail.
    --embed-thumbnail


    # Embed downloaded subtitles into the final MKV.
    --embed-subs


    # Download creator-provided subtitles.
    #
    # Automatic subtitles are intentionally excluded because they
    # previously triggered YouTube HTTP 429 rate limiting.
    --write-subs


    # Request English and Hindi subtitle variants only.
    --sub-langs "en.*,hi.*"


    # Reuse the current Chrome session for videos that require login,
    # age verification, or other session-dependent access.
    --cookies-from-browser brave


    # Download up to four DASH/HLS fragments concurrently.
    -N 4


    # Keep retrying temporary network/server failures.
    --retries infinite
    --fragment-retries infinite


    # Gradually increase the delay after failed requests.
    --retry-sleep "http:exp=1:20"
    --retry-sleep "fragment:exp=1:20"


    # Destination selected above.
    -P "$output_dir"


    # Human-readable filename while preserving the unique YouTube ID.
    -o "%(title)s [%(id)s].%(ext)s"
  )


  # ------------------------------------------------------------
  # 6. Download
  # ------------------------------------------------------------

  yt-dlp "${args[@]}" "$url"
}
