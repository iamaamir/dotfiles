# Define a generic function to source files if they exist
source_if_exists() {
    local files=("$@")
    local failed_files=()

    for file_path in "${files[@]}"; do
        if [ -f "$file_path" ]; then
            if ! source "$file_path"; then
                failed_files+=("$file_path")
            fi
        else
            failed_files+=("$file_path")
        fi
    done

    if [ ${#failed_files[@]} -gt 0 ]; then
        print "Failed to source files:"
        for file in "${failed_files[@]}"; do
            print "  - $file"
        done
    fi
}

