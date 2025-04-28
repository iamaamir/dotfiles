#!/bin/bash

# Base directory where all workspaces are stored
BASE_NOTES_DIR=~/notes
CURRENT_WORKSPACE_FILE="$BASE_NOTES_DIR/.current_workspace"

# Load or set the current workspace to default
function load_current_workspace {
    if [[ -f "$CURRENT_WORKSPACE_FILE" ]]; then
        CURRENT_WORKSPACE=$(<"$CURRENT_WORKSPACE_FILE")
    else
        CURRENT_WORKSPACE="default"
        echo "$CURRENT_WORKSPACE" > "$CURRENT_WORKSPACE_FILE"
    fi
    NOTES_DIR="$BASE_NOTES_DIR/$CURRENT_WORKSPACE"
}

# Save current workspace
function save_current_workspace {
    echo "$CURRENT_WORKSPACE" > "$CURRENT_WORKSPACE_FILE"
}

# Load current workspace on script start
load_current_workspace

# Ensure base and current workspace directories exist
if [ ! -d "$BASE_NOTES_DIR" ]; then
    mkdir -p "$BASE_NOTES_DIR/$CURRENT_WORKSPACE"
    echo "Created base notes directory at $BASE_NOTES_DIR with default workspace."
fi

# Dashboard displaying overall system stats
function dash {
    clear
    
    # Calculate total notes, total workspaces, and workspace size
    note_count=$(find "$NOTES_DIR" -type f -name "*.md" | wc -l | tr -d ' ')
    total_workspaces=$(find "$BASE_NOTES_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
    workspace_size=$(du -sh "$NOTES_DIR" 2>/dev/null | cut -f1)

    echo -e "\033[1;34m=====================================================\033[0m"
    echo -e "\033[1;34m||            \033[1;33m📝 Note Management Dashboard\033[0m             \033[1;34m||\033[0m"
    echo -e "\033[1;34m=====================================================\033[0m"
    echo -e "\033[1;35m📂 Current Workspace: \033[1;32m$CURRENT_WORKSPACE\033[0m"
    echo -e "\033[1;35m📄 Total Notes: \033[1;32m$note_count\033[0m"
    echo -e "\033[1;35m🗄️ Total Workspaces: \033[1;32m$total_workspaces\033[0m"
    echo -e "\033[1;35m📏 Workspace Size: \033[1;32m$workspace_size\033[0m"
    
    echo -e "\n\033[1;34m>> Last Modified Note <<\033[0m"
    recent_note=$(find "$NOTES_DIR" -type f -name "*.md" -print0 | xargs -0 stat -f "%m %N" 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)
    if [ -n "$recent_note" ]; then
        recent_note_name=$(basename "$recent_note")
        recent_modified_time=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$recent_note" 2>/dev/null)
        echo -e "\033[1;33m✨ $recent_note_name\033[0m"
        echo -e "   🕒 \033[1;32m$recent_modified_time\033[0m"
    else
        echo -e "\033[1;31m⚠️ No recent notes found.\033[0m"
    fi

    echo -e "\n\033[1;34m>> Recent Activity & Details <<\033[0m"
    recent_notes=$(find "$NOTES_DIR" -type f -name "*.md" -print0 | xargs -0 stat -f "%m %N" 2>/dev/null | sort -nr | head -n 5 | cut -d' ' -f2-)
    if [ -n "$recent_notes" ]; then
        for note in $recent_notes; do
            name=$(basename "$note")
            mod_time=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$note" 2>/dev/null)
            line_count=$(wc -l < "$note" | tr -d ' ')
            char_count=$(wc -m < "$note" | tr -d ' ')
            tags=$(grep "^#tags:" "$note" 2>/dev/null | sed 's/#tags: //' | tr ',' ' ')

            echo -e "\033[1;33m🗒️ $name\033[0m"
            echo -e "   - 🕒 \033[1;32m$mod_time\033[0m"
            echo -e "   - 📏 Lines: \033[1;32m$line_count\033[0m | Characters: \033[1;32m$char_count\033[0m"
            if [ -n "$tags" ]; then
                echo -e "   - 🏷️ Tags: \033[1;35m$tags\033[0m"
            else
                echo -e "   - 🚫 Tags: \033[1;31mNone\033[0m"
            fi
        done
    else
        echo -e "\033[1;31m⚠️ No recent activity found.\033[0m"
    fi

    echo -e "\n\033[1;34m>> Top Tags <<\033[0m"
    tags_summary=$(grep -rh "^#tags:" "$NOTES_DIR" 2>/dev/null | tr ',' '\n' | sed 's/#tags: //' | tr ' ' '\n' | sort | uniq -c | sort -nr | head -n 3)
    if [ -n "$tags_summary" ]; then
        echo -e "\033[1;35m$tags_summary\033[0m"
    else
        echo -e "\033[1;31m⚠️ No tags found.\033[0m"
    fi
    
    echo -e "\033[1;34m=====================================================\033[0m"
}

# List all workspaces with a tree view of notes
function list_all {
    echo "Workspaces and their notes:"
    shopt -s nullglob
    for workspace in "$BASE_NOTES_DIR"/*/; do
        workspace_name=$(basename "$workspace")
        echo -e "Workspace: \033[1;33m$workspace_name\033[0m"
        eza --tree "$workspace" --icons
    done
    shopt -u nullglob
}

# Interactive workspace switcher
function switch_workspace {
    workspace=$(ls "$BASE_NOTES_DIR" | fzf --prompt="Select a workspace to switch: ")
    if [ -n "$workspace" ]; then
        CURRENT_WORKSPACE="$workspace"
        NOTES_DIR="$BASE_NOTES_DIR/$CURRENT_WORKSPACE"
        save_current_workspace
        echo "Switched to workspace '$CURRENT_WORKSPACE'."
    else
        echo "No workspace selected."
    fi
}

# Show current workspace
function display_current_workspace {
    echo "Current workspace: '$CURRENT_WORKSPACE'"
}

# List notes in current workspace
function list_notes {
    display_current_workspace
    eza --tree "$NOTES_DIR" --icons
}

# View notes
function view_notes {
    display_current_workspace
    note=$(find "$NOTES_DIR" -type f -name "*.md" | fzf --prompt="Select a note to view: ")
    if [ -n "$note" ]; then
        bat "$note"
    else
        echo "No note selected."
    fi
}

# Edit notes
function edit_note {
    display_current_workspace
    note=$(find "$NOTES_DIR" -type f -name "*.md" | fzf --prompt="Select a note to edit: ")
    if [ -n "$note" ]; then
        ${EDITOR:-vim} "$note"
    else
        echo "No note selected."
    fi
}

# Create a new note
function new_note {
    display_current_workspace
    read -p "Enter note title: " title
    ${EDITOR:-nvim} "$NOTES_DIR/$title.md"
}

# Search notes by content
function search_notes_content {
    display_current_workspace
    result=$(grep -rnw "$NOTES_DIR" -e "$1" --include \*.md | fzf --prompt="Search results for '$1': ")
    note=$(echo "$result" | awk -F: '{print $1}' | uniq)
    if [ -n "$note" ]; then
        bat "$note"
    else
        echo "No matching notes found."
    fi
}

# Search notes by tags
function search_notes_tags {
    display_current_workspace
    tag=$(grep -rh "^#tags:" "$NOTES_DIR" | sed 's/#tags: //' | tr ',' '\n' | fzf --prompt="Search for tag: ")
    if [ -n "$tag" ]; then
        note=$(grep -rl "#tags:.*$tag" "$NOTES_DIR" | fzf --prompt="Notes with tag '$tag': ")
        if [ -n "$note" ]; then
            bat "$note"
        else
            echo "No notes found with tag '$tag'."
        fi
    else
        echo "No tag selected."
    fi
}

# Show help
function show_help {
    echo "Usage: note {all|sw|ls|view|edit|new|search <keyword>|tags|dash|help}"
    echo
    echo "Commands:"
    echo "  all          List all workspaces and their notes"
    echo "  sw           Switch workspace (interactive)"
    echo "  ls           List notes in the current workspace"
    echo "  view         View a note with syntax highlighting"
    echo "  edit         Edit a note using the environment's default editor"
    echo "  new          Create a new note"
    echo "  search       Search notes content for a keyword"
    echo "  tags         Search and view notes by tags"
    echo "  dash         View a detailed summary of the dashboard"
    echo "  help         Show this help message"
    echo
    echo "How to Define Tags:"
    echo "  Add a line at the top or bottom of your note for tags."
    echo "  Use the format: #tags: tag1, tag2, tag3"
    echo "  Example:"
    echo "    #tags: work, ideas, project"
    echo "  These tags can then be searched using the 'tags' command."
}

# Main command handler
case "$1" in
    all)
        list_all
        ;;
    sw)
        switch_workspace
        ;;
    ls)
        list_notes
        ;;
    view)
        view_notes
        ;;
    edit)
        edit_note
        ;;
    new)
        new_note
        ;;
    search)
        if [ -n "$2" ]; then
            search_notes_content "$2"
        else
            echo "Provide a search keyword, e.g., note search keyword"
        fi
        ;;
    tags)
        search_notes_tags
        ;;
    dash)
        dash
        ;;
    help|-h|--help|'')
        show_help
        ;;
    *)
        echo "Invalid command. Use 'note help' for usage information."
        ;;
esac
