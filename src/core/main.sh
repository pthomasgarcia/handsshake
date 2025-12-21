#!/usr/bin/env bash
# shellcheck shell=bash
if [[ -z "${HANDSSHAKE_LOADED:-}" ]]; then
    HANDSSHAKE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    HANDSSHAKE_LOADED=true
fi

# Source lib and util modules
source "$HANDSSHAKE_SCRIPT_DIR/../lib/config.sh"
source "$HANDSSHAKE_SCRIPT_DIR/../util/file_utils.sh"
source "$HANDSSHAKE_SCRIPT_DIR/../util/logging_utils.sh"
source "$HANDSSHAKE_SCRIPT_DIR/../util/validation_utils.sh"

# Load Configuration (XDG-aware)
load_config

# Source Services
source "$HANDSSHAKE_SCRIPT_DIR/../services/agent_service.sh"
source "$HANDSSHAKE_SCRIPT_DIR/../services/key_service.sh"
source "$HANDSSHAKE_SCRIPT_DIR/../services/health_service.sh"

########################################
# Environment & Dependency Validation
########################################

validate_dependency() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error_exit "Required command '$cmd' not found."
    fi
    return 0
}

validate_environment() {
    local dependencies=(ssh-agent ssh-add awk pgrep kill flock realpath)
    for dep in "${dependencies[@]}"; do
        validate_dependency "$dep"
    done
    return 0
}

########################################
# Command Dispatch Module
########################################

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [arguments]

Commands:
  add [key_file]         : Add a key (default: ~/.ssh/id_rsa).
  remove <key_file>      : Remove a specific key.
  remove-all             : Remove all keys from the agent and records.
  list                   : List keys currently managed by the agent.
  timeout <seconds>      : Update timeout for all recorded keys.
  cleanup                : Kill agent processes and remove socket files.
  health                 : Check SSH environment health.
  help                   : Display this help message.

Arguments:
  key_file    Path to the SSH key file.
  seconds     New timeout in seconds (positive integer, max 86400).
EOF
    return 1
}

dispatch() {
    local command=""
    local key_file=""
    local new_timeout=""

    if [[ "$#" -eq 0 ]]; then
        usage
        return $?
    fi

    # Argument Parsing
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            add|remove|remove-all|list|timeout|cleanup|health)
                command="$1"
                shift
                ;;
            -h|--help)
                usage
                return $?
                ;;
            *)
                if [[ -z "$key_file" ]] && [[ -z "$new_timeout" ]]; then
                    if [[ "$command" == "add" ]] || [[ "$command" == "remove" ]]; then
                        key_file="$1"
                    elif [[ "$command" == "timeout" ]]; then
                        new_timeout="$1"
                    else
                        echo "Error: Unexpected argument '$1'." >&2
                        usage
                        return $?
                    fi
                else
                    echo "Error: Too many arguments for command '$command'." >&2
                    usage
                    return $?
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$command" ]]; then
        echo "Error: No command specified." >&2
        usage
        return $?
    fi

    # Command Execution
    case "$command" in
        add)
            # key_file is optional, defaults handled in add_key
            run_with_lock "$HANDSSHAKE_LOCK_FILE" add_key "$key_file"
            ;;
        remove)
            if [[ -z "$key_file" ]]; then
                echo "Error: Missing key_file for 'remove' command." >&2
                usage
                return $?
            fi
            run_with_lock "$HANDSSHAKE_LOCK_FILE" remove_key "$key_file"
            ;;
        remove-all)
            run_with_lock "$HANDSSHAKE_LOCK_FILE" remove_all_keys
            ;;
        list)
            ensure_agent # ensure agent is running/loaded before listing
            list_keys
            ;;
        timeout)
            if [[ -z "$new_timeout" ]]; then
                echo "Error: Missing timeout in seconds for 'timeout' command." >&2
                usage
                return $?
            fi
            run_with_lock "$HANDSSHAKE_LOCK_FILE" update_key_timeout "$new_timeout"
            ;;
        cleanup)
            run_with_lock "$HANDSSHAKE_LOCK_FILE" cleanup_agent
            ;;
        health)
            check_health
            ;;
        *)
            echo "Error: Unknown command '$command'." >&2
            usage
            return $?
            ;;
    esac
    return 0
}

########################################
# Main Execution
########################################

main() {
    validate_environment
    
    # Ensure agent is running/env is loaded for all commands that might need it.
    # We use a lock to prevent race conditions during startup.
    # Note: 'cleanup' might not strictly need it, but consistent env matches are good.
    # 'health' is read-only validation.
    # We'll allow 'health' and 'cleanup' to run without forced ensure_agent if possible,
    # but ensure_agent is idempotent and fast if already running.
    
    run_with_lock "$HANDSSHAKE_LOCK_FILE" ensure_agent
    
    # Check if script is being sourced (setup aliases) or executed (dispatch command)
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        # Script is being executed directly
        if [[ "$1" == "health" ]] || [[ "$1" == "list" ]] || [[ "$1" == "cleanup" ]]; then
             # Allow informational/cleanup commands even if not sourced, 
             # but warn that env changes won't persist.
             echo -e "\033[1;33mNote:\033[0m handsshake is running as a sub-process. Environment variables will not persist in your shell." >&2
        else
             echo -e "\033[1;31mWarning:\033[0m handsshake must be SOURCED to modify your shell environment." >&2
             echo "Usage: source $(basename "$0") <command>" >&2
             echo "Or ensure your alias is: alias handsshake='source $(realpath "$0")'" >&2
        fi
        dispatch "$@"
    else
        # Script is sourced
        # If arguments provided, run dispatch immediately
        if [[ "$#" -gt 0 ]]; then
            dispatch "$@"
        else
            # If sourced with no args (e.g. in .bashrc), just ensure agent and return
            :
        fi
    fi
    return 0
}

main "$@"
