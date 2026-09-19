#!/bin/bash

# ask - Natural Language to Command Converter
# Uses Ollama to convert natural language queries to CLI commands

set -euo pipefail

# Configuration (ASK_CONFIG overrides the config file location for tests)
CONFIG_DIR="${HOME}/.config/ask"
CONFIG_FILE="${ASK_CONFIG:-${CONFIG_DIR}/config}"
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
TEMPERATURE="0.1"

# Load saved model from config
MODEL="${CC_MODEL:-}"
if [ -z "$MODEL" ] && [ -f "$CONFIG_FILE" ]; then
    MODEL=$(jq -r '.model // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
fi

# Detect shell and OS for context
SHELL_NAME="$(basename "$SHELL")"
OS_TYPE="$(uname -s)"
OS_VERSION=""

# Get OS-specific details
case "$OS_TYPE" in
    Darwin)
        OS_TYPE="macOS"
        OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
        ;;
    Linux)
        OS_TYPE="Linux"
        if [ -f /etc/os-release ]; then
            OS_VERSION="$(source /etc/os-release && echo "$PRETTY_NAME")"
        fi
        ;;
esac

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Function to check if ollama is running
check_ollama() {
    if ! curl -s --max-time 10 "${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
        echo -e "${RED}Error: Ollama is not running or not accessible at ${OLLAMA_HOST}${NC}" >&2
        echo "Please start ollama service or check your OLLAMA_HOST setting" >&2
        exit 1
    fi
}

# Function to save selected model to config
save_model() {
    local model_name="$1"
    mkdir -p "$CONFIG_DIR"
    jq -n --arg model "$model_name" '{model: $model}' > "$CONFIG_FILE"
    echo -e "${GREEN}Model saved to config: $model_name${NC}" >&2
}

# Function to show current config
show_config() {
    if [ -f "$CONFIG_FILE" ]; then
        echo "Current configuration:" >&2
        cat "$CONFIG_FILE" >&2
    else
        echo "No configuration file found. Using defaults." >&2
    fi
}

# Function to reset config
reset_config() {
    if [ -f "$CONFIG_FILE" ]; then
        rm -f "$CONFIG_FILE"
        echo -e "${GREEN}Configuration reset.${NC}" >&2
    fi
}

# Function to pull a model
pull_model() {
    local model_name="$1"
    echo -e "${YELLOW}Pulling model ${model_name}...${NC}" >&2
    
    # Build JSON safely using jq to prevent injection
    local payload
    payload=$(jq -n --arg name "$model_name" '{name: $name}')
    
    if curl -s --max-time 300 -X POST "${OLLAMA_HOST}/api/pull" -d "$payload" >/dev/null 2>&1; then
        echo -e "${GREEN}Model pulled successfully!${NC}" >&2
        return 0
    else
        echo -e "${RED}Error: Failed to pull model ${model_name}${NC}" >&2
        return 1
    fi
}

# Function to select model interactively
select_model() {
    echo "Fetching available models..." >&2
    
    # Get models list
    local models_json
    models_json=$(curl -s --max-time 10 "${OLLAMA_HOST}/api/tags" 2>/dev/null)
    
    # Check if we got a valid response
    if [ -z "$models_json" ] || ! echo "$models_json" | jq -e . >/dev/null 2>&1; then
        echo -e "${YELLOW}Could not fetch models. Pulling default model llama3.2...${NC}" >&2
        if pull_model "llama3.2"; then
            echo "llama3.2"
            return
        else
            exit 1
        fi
    fi
    
    # Extract model names
    local models
    models=$(echo "$models_json" | jq -r '.models[].name' 2>/dev/null || true)
    
    # Check if we have models
    if [ -z "$models" ]; then
        echo -e "${YELLOW}No models found. Pulling default model llama3.2...${NC}" >&2
        if pull_model "llama3.2"; then
            echo "llama3.2"
            return
        else
            exit 1
        fi
    fi
    
    # Convert to array
    local model_array=()
    while IFS= read -r line; do
        model_array+=("$line")
    done <<< "$models"
    
    if [ ${#model_array[@]} -eq 0 ]; then
        echo -e "${RED}Error: No models available${NC}" >&2
        exit 1
    fi
    
    echo "Available models:" >&2
    for i in "${!model_array[@]}"; do
        echo "$((i+1)). ${model_array[$i]}" >&2
    done
    
    local choice
    while true; do
        echo -n "Select model (1-${#model_array[@]}): " >&2
        read -r choice
        
        # Handle empty input
        if [ -z "$choice" ]; then
            echo -e "${RED}Please enter a number${NC}" >&2
            continue
        fi
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#model_array[@]}" ]; then
            local selected_model="${model_array[$((choice-1))]}"
            save_model "$selected_model"
            echo "$selected_model"
            return
        else
            echo -e "${RED}Invalid choice. Please enter a number between 1 and ${#model_array[@]}.${NC}" >&2
        fi
    done
}

# Function to get command from natural language
get_command() {
    local query="$1"
    local feedback="${2:-}"
    local attempt="${3:-1}"
    
    # Use significantly higher temperature for regeneration attempts
    local temp="$TEMPERATURE"
    if [ "$attempt" -gt 1 ]; then
        temp="0.5"
    fi
    
    # System prompt for precise command generation
    local system_prompt="You are an expert CLI command generator that outputs precise, working shell commands.

OUTPUT FORMAT:
- Output ONLY the command - no explanations, no markdown, no quotes, no backticks
- Use bash/zsh syntax
- Prefer portable POSIX commands when possible
- Use proper escaping for paths with spaces

IMPORTANT GUIDELINES:
1. Always verify flags/options exist for the command before outputting
2. If unsure about a flag, do NOT use it - use safer alternatives
3. Prefer simpler commands over complex ones
4. Include safety flags (e.g., -i for rm, -v for cp/mv, -n for dry-run when available)

CRITICAL: Double-check your command before outputting. Common mistakes:
- Using flags that do not exist for a command
- Incorrect flag syntax

If the command is complex, break it down into simpler, verified parts."

    # Build user prompt - include feedback and previous command in the actual prompt
    local user_prompt="$query"
    # Single channel: exported FEEDBACK/PREV_COMMAND (set by retry loop) win
    # over the passed-in feedback parameter. Declared local so nothing leaks.
    local fb="${FEEDBACK:-${feedback:-}}"
    local prev_cmd="${PREV_COMMAND:-}"
    if [ -n "$fb" ]; then
        user_prompt="${user_prompt}

--- PREVIOUS COMMAND (DO NOT REPEAT THIS) ---
Command: ${prev_cmd}
Error/Feedback: ${fb}

INSTRUCTIONS:
1. Generate a DIFFERENT command that fixes the above error
2. Do NOT use the same flags or syntax that caused the error
3. If unsure about a flag, do NOT use it - use safer alternatives
4. Output ONLY the new working command - no explanations"
    fi
    
    system_prompt="${system_prompt}

EXAMPLES:
User: \"delete all log files\"
Output: find . -name "*.log" -type f -delete

User: \"show disk usage\"
Output: df -h

User: \"find files modified today\"
Output: find . -mtime -1 -type f

CONTEXT: Running on ${SHELL_NAME} on ${OS_TYPE} ${OS_VERSION}"
    
    # Verbose output
    if [ "${VERBOSE:-false}" = "true" ]; then
        printf "${CYAN}═══════════════════════════════════════${NC}\n" >&2
        printf "${CYAN}  VERBOSE MODE - Attempt #%d${NC}\n" "$attempt" >&2
        printf "${CYAN}═══════════════════════════════════════${NC}\n" >&2
        printf "${YELLOW}Temperature:${NC} %s\n" "$temp" >&2
        printf "${YELLOW}Query:${NC} %s\n" "$query" >&2
        if [ -n "$fb" ]; then
            printf "${YELLOW}Feedback:${NC} %s\n" "$fb" >&2
            printf "${YELLOW}Prev Command:${NC} %s\n" "${prev_cmd:-none}" >&2
        fi
        printf "\n${YELLOW}--- USER PROMPT ---${NC}\n%s\n" "$user_prompt" >&2
        printf "${YELLOW}--- SYSTEM PROMPT ---${NC}\n%s\n" "$system_prompt" >&2
        printf "${CYAN}═══════════════════════════════════════${NC}\n\n" >&2
    fi
    
    # Prepare JSON payload
    local payload
    payload=$(jq -n \
        --arg model "$MODEL" \
        --arg prompt "$user_prompt" \
        --arg system "$system_prompt" \
        --argjson options "{\"temperature\": $temp}" \
        '{
            model: $model,
            prompt: $prompt,
            system: $system,
            options: $options,
            stream: false
        }')
    
    # Debug: show the payload if verbose
    if [ "${VERBOSE:-false}" = "true" ]; then
        echo -e "${BLUE}API Request:${NC}" >&2
        echo "$payload" | jq '.' >&2
    fi
    
    # Make API call with loading indicator
    local response
    local curl_exit
    
    # Show loading indicator
    if [ "${VERBOSE:-false}" != "true" ]; then
        printf "${YELLOW}Generating command...${NC}" >&2
    fi
    
    response=$(curl -s --max-time 60 -X POST "${OLLAMA_HOST}/api/generate" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null) || curl_exit=$?
    
    # Clear loading indicator
    if [ "${VERBOSE:-false}" != "true" ]; then
        printf "\r                        \r" >&2
    fi
    
    # Check if curl failed
    if [ -n "${curl_exit:-}" ]; then
        printf "${RED}Error: Failed to connect to Ollama (exit code %d)${NC}\n" "$curl_exit" >&2
        if [ "$curl_exit" -eq 28 ]; then
            printf "${YELLOW}Request timed out after 60 seconds${NC}\n" >&2
        fi
        return 1
    fi
    
    # Debug: show the response if verbose
    if [ "${VERBOSE:-false}" = "true" ]; then
        echo -e "${BLUE}API Response:${NC}" >&2
        echo "$response" | jq '.' >&2
    fi
    
    # Check if response is empty
    if [ -z "$response" ]; then
        printf "${RED}Error: Empty response from Ollama${NC}\n" >&2
        printf "${YELLOW}Check if Ollama is running at ${OLLAMA_HOST}${NC}\n" >&2
        return 1
    fi
    
    # Check if response is valid JSON
    if ! echo "$response" | jq -e . >/dev/null 2>&1; then
        printf "${RED}Error: Invalid JSON response from Ollama${NC}\n" >&2
        printf "${YELLOW}Response:${NC}\n" >&2
        echo "$response" | head -20 >&2
        return 1
    fi
    
    # Check for Ollama error response
    local ollama_error
    ollama_error=$(echo "$response" | jq -r '.error // empty' 2>/dev/null)
    if [ -n "$ollama_error" ]; then
        printf "${RED}Ollama Error: %s${NC}\n" "$ollama_error" >&2
        return 1
    fi
    
    # Extract the response text and clean it up
    local command
    command=$(echo "$response" | jq -r '.response // empty' 2>/dev/null)
    
    if [ -z "$command" ] || [ "$command" = "null" ]; then
        return 1
    fi
    
    command=$(echo "$command" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -n 1)
    
    # If explain mode is on, get explanation
    if [ "${EXPLAIN:-false}" = "true" ]; then
        local explain_payload
        explain_payload=$(jq -n \
            --arg model "$MODEL" \
            --arg cmd "$command" \
            '{
                model: $model,
                prompt: "Explain this CLI command briefly:\n\nCommand: \($cmd)\n\nFormat:\nWHAT: [1 line what it does]\nPARTS:\n- [first part: what it does]\n- [second part: what it does]\nOUTPUT: [1 line what it outputs]\n\nKeep each part on one line. No backticks, no markdown.",
                stream: false
            }')
        
        # Show loading for explanation
        if [ "${VERBOSE:-false}" != "true" ]; then
            printf "${YELLOW}Getting explanation...${NC}" >&2
        fi
        
        local explain_response
        explain_response=$(curl -s --max-time 30 -X POST "${OLLAMA_HOST}/api/generate" \
            -H "Content-Type: application/json" \
            -d "$explain_payload" 2>/dev/null)
        
        # Clear loading indicator
        if [ "${VERBOSE:-false}" != "true" ]; then
            printf "\r                        \r" >&2
        fi
        
        if echo "$explain_response" | jq -e . >/dev/null 2>&1; then
            local explanation
            explanation=$(echo "$explain_response" | jq -r '.response // empty' 2>/dev/null)
            if [ -n "$explanation" ] && [ "$explanation" != "null" ]; then
                explanation=$(echo "$explanation" | sed 's/`//g' | sed 's/\*\*//g')
                
                printf "\n"
                printf "${YELLOW}╭─────────────────────────────────────────────╮${NC}\n"
                printf "${YELLOW}│${NC}  ${GREEN}COMMAND EXPLANATION${NC}                      ${YELLOW}│${NC}\n"
                printf "${YELLOW}╰─────────────────────────────────────────────╯${NC}\n"
                echo "$explanation" | sed 's/^/  /'
                printf "\n"
            fi
        fi
    fi
    
    # Show the command with colors using printf
    printf "${GREEN}%s${NC}\n" "$command"
    
    # Ask user what to do
    printf "\n"
    printf "${BLUE}%s${NC}\n" "What would you like to do?"
    printf "  ${YELLOW}r${NC} - Run the command\n"
    printf "  ${YELLOW}t${NC} - Test run (auto-regenerate on error)\n"
    printf "  ${YELLOW}c${NC} - Copy to clipboard\n"
    printf "  ${YELLOW}g${NC} - Generate again (incorrect)\n"
    printf "  ${YELLOW}q${NC} - Quit\n"
    printf "\n"
    printf "Your choice [r/t/c/g/q]: "
    
    local choice
    read -r choice
    
    case "$choice" in
            r|R)
            if [ "${DRY_RUN:-false}" = "true" ]; then
                printf "${YELLOW}DRY RUN - Would execute:${NC}\n"
                printf "${GREEN}%s${NC}\n" "$command"
            else
                printf "${BLUE}Running: %s${NC}\n" "$command"
                printf "${YELLOW}Are you sure? [y/N]: ${NC}"
                local confirm
                read -r confirm
                if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                    printf "Cancelled\n"
                    return 0
                fi
                printf "\n"
                eval "$command"
            fi
            return 0
            ;;
        t|T)
            printf "${BLUE}Test running: %s${NC}\n" "$command"
            printf "${YELLOW}──────────────── OUTPUT ────────────────${NC}\n"
            local cmd_output
            local cmd_exit
            cmd_output=$(eval "$command" 2>&1) || cmd_exit=$?
            printf "%s\n" "$cmd_output"
            printf "${YELLOW}─────────────────────────────────────────${NC}\n"
            
            if [ -n "${cmd_exit:-}" ]; then
                printf "${RED}Command exited with code: %s${NC}\n" "$cmd_exit"
                printf "\n${YELLOW}Auto-regenerating with error as feedback...${NC}\n"
                FEEDBACK="Command failed with error: $cmd_output"
                export FEEDBACK
                export PREV_COMMAND="$command"
                return 2
            else
                printf "${GREEN}Command succeeded!${NC}\n"
                return 0
            fi
            ;;
        c|C)
            if command -v pbcopy >/dev/null 2>&1; then
                echo "$command" | pbcopy
            elif command -v xclip >/dev/null 2>&1; then
                echo "$command" | xclip -selection clipboard
            elif command -v xsel >/dev/null 2>&1; then
                echo "$command" | xsel --clipboard
            else
                printf "${YELLOW}No clipboard tool found. Command: %s${NC}\n" "$command"
                return 1
            fi
            printf "${GREEN}%s${NC}\n" "✓ Copied to clipboard"
            return 0
            ;;
        g|G)
            printf "${YELLOW}The command was incorrect. Please explain what went wrong:${NC}\n"
            printf "Feedback: "
            read -r FEEDBACK
            # Store the previous command for the model to see (export for child processes)
            export PREV_COMMAND="$command"
            export FEEDBACK
            if [ -n "$FEEDBACK" ]; then
                printf "${BLUE}Regenerating with feedback...${NC}\n"
                return 2
            else
                printf "${YELLOW}Regenerating without feedback...${NC}\n"
                return 2
            fi
            ;;
        q|Q|*)
            printf "Cancelled\n"
            return 0
            ;;
    esac
}

# Function to show usage
show_usage() {
    cat << EOF
ask - Convert natural language to CLI commands

Usage: $0 [OPTIONS] "natural language query"

Examples:
  $0 "how to commit"
  $0 "list all files including hidden ones"
  $0 "find files containing specific text"

Options:
  -h, --help      Show this help message
  -v, --verbose   Show additional information
  --model MODEL   Specify Ollama model to use
  --config        Show current configuration
  --reset-config  Reset configuration (clear saved model)
  --explain       Explain what the command does before showing it
  --dry-run       Show command without executing it

Environment Variables:
  CC_MODEL        Default model to use (overrides config)
  OLLAMA_HOST     Ollama API endpoint (default: http://localhost:11434)

Configuration:
  Selected model is saved to ~/.config/ask/config
  Use --model to temporarily override, --reset-config to clear

EOF
}

# Function to check required dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v curl >/dev/null 2>&1; then
        missing_deps+=("curl")
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}Error: Missing required dependencies: ${missing_deps[*]}${NC}" >&2
        echo "Please install these tools:" >&2
        if [[ "$OS_TYPE" == "Darwin" ]] || [[ "$OSTYPE" == "darwin"* ]]; then
            echo "  brew install curl jq" >&2
        elif command -v apt-get >/dev/null 2>&1; then
            echo "  sudo apt-get install curl jq" >&2
        elif command -v yum >/dev/null 2>&1; then
            echo "  sudo yum install curl jq" >&2
        fi
        exit 1
    fi
}

# Ensure a named model exists locally, pulling it on demand.
# Pure transport check: GET /api/tags, pull when absent. No globals mutated.
ensure_model_available() {
    local wanted="$1"
    local model_response
    model_response=$(curl -s --max-time 10 "${OLLAMA_HOST}/api/tags" 2>/dev/null)

    if [ -n "$model_response" ] && echo "$model_response" | jq -e . >/dev/null 2>&1; then
        local model_exists
        model_exists=$(echo "$model_response" | jq -r --arg m "$wanted" '.models[] | select(.name == $m) | .name' 2>/dev/null || echo "")

        if [ -z "$model_exists" ]; then
            echo -e "${YELLOW}Model ${wanted} not found. Pulling model...${NC}" >&2
            pull_model "$wanted" || true
        fi
    fi
}

# Resolve which model to use. Precedence: $MODEL (from --model flag or
# CC_MODEL env) > saved config (already loaded into $MODEL) > interactive
# selection. Prints the model name; caller assigns MODEL=$(resolve_model).
resolve_model() {
    local is_verbose="${1:-false}"
    if [ -n "${MODEL:-}" ]; then
        ensure_model_available "$MODEL"
        echo "$MODEL"
        return 0
    fi
    if [ "$is_verbose" = true ]; then
        echo -e "${BLUE}No model specified. Selecting from available models...${NC}" >&2
    fi
    local picked
    picked=$(select_model)
    echo -e "${GREEN}Selected model: $picked${NC}" >&2
    echo "$picked"
}

# Main function
main() {
    local verbose=false
    local query=""
    
    # Parse arguments (allow flags both before and after query)
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                verbose=true
                export VERBOSE=true
                shift
                ;;
            --model)
                if [ -n "${2:-}" ]; then
                    MODEL="$2"
                    shift 2
                else
                    echo -e "${RED}Error: --model requires a value${NC}" >&2
                    exit 1
                fi
                ;;
            --config)
                show_config
                exit 0
                ;;
            --reset-config)
                reset_config
                exit 0
                ;;
            --dry-run)
                DRY_RUN=true
                export DRY_RUN
                shift
                ;;
            --explain)
                EXPLAIN=true
                export EXPLAIN
                shift
                ;;
            --)
                shift
                query="$*"
                break
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                show_usage
                exit 1
                ;;
            *)
                # First non-option arg - could be query or start of query with trailing flags
                query="$1"
                shift
                # Check remaining args for more query parts or trailing flags
                while [[ $# -gt 0 ]]; do
                    case $1 in
                        --dry-run)
                            DRY_RUN=true
                            export DRY_RUN
                            shift
                            ;;
                        --explain)
                            EXPLAIN=true
                            export EXPLAIN
                            shift
                            ;;
                        -*)
                            echo -e "${RED}Unknown option: $1${NC}" >&2
                            show_usage
                            exit 1
                            ;;
                        *)
                            query="$query $1"
                            shift
                            ;;
                    esac
                done
                break
                ;;
        esac
    done
    
    # Trim leading/trailing whitespace from query
    query=$(echo "$query" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    if [ -z "$query" ]; then
        echo -e "${RED}Error: Please provide a natural language query${NC}" >&2
        show_usage
        exit 1
    fi
    
    # Check prerequisites
    check_dependencies
    check_ollama
    
    # Select model if not specified (single precedence chain in resolve_model)
    MODEL=$(resolve_model "$verbose")
    
    if [ "$verbose" = true ]; then
        echo -e "${BLUE}Query:${NC} $query" >&2
        echo -e "${BLUE}Model:${NC} $MODEL" >&2
        echo -e "${BLUE}Generating command...${NC}" >&2
    fi
    
    # Get and display the command with retry loop
    local feedback=""
    local attempt=1
    local max_attempts=3
    
    while [ $attempt -le $max_attempts ]; do
        local result
        if get_command "$query" "$feedback" "$attempt"; then
            # Success - command executed or copied
            return 0
        else
            result=$?
            if [ $result -eq 2 ]; then
                # User wants to regenerate
                attempt=$((attempt + 1))
                if [ $attempt -le $max_attempts ]; then
                    printf "${YELLOW}Regenerating (attempt %d/%d)...${NC}\n" $attempt $max_attempts
                    continue
                else
                    printf "${RED}Max attempts reached. Please try again with a different query.${NC}\n"
                    return 1
                fi
            else
                # Other error
                return 1
            fi
        fi
    done
}

# Run main function with all arguments
main "$@"

