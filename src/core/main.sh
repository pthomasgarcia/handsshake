#!/usr/bin/env bash

# shellcheck shell=bash
if [[ -z "${HANDSSHAKE_LOADED:-}" ]]; then
    HANDSSHAKE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    HANDSSHAKE_LOADED=true
fi

# Source core utilities (Bootstrapping)
# shellcheck source=/dev/null
source "$HANDSSHAKE_SCRIPT_DIR/../util/logging_utils.sh"
# shellcheck source=/dev/null
source "$HANDSSHAKE_SCRIPT_DIR/../util/file_utils.sh"

# Use assert_source for the remaining modules
assert_source "$HANDSSHAKE_SCRIPT_DIR/../lib/config.sh"
assert_source "$HANDSSHAKE_SCRIPT_DIR/../util/validation_utils.sh"

# Load Configuration (XDG-aware)
load_config

# Source Services
assert_source "$HANDSSHAKE_SCRIPT_DIR/../services/agent_service.sh"
assert_source "$HANDSSHAKE_SCRIPT_DIR/../services/key_service.sh"
assert_source "$HANDSSHAKE_SCRIPT_DIR/../services/health_service.sh"

########################################
# Environment & Dependency Validation
########################################

validate_dependency() {
    local cmd="$1"
    if ! command -v "$cmd" > /dev/null 2>&1; then
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
    local exit_code="${1:-0}"
    cat << EOF
Usage: $(basename "$0") <command> [arguments]

Commands:
  attach [key_file]      : Attach key to agent (default: ~/.ssh/id_ed25519).
  detach <key_file>      : Detach a specific key from the agent.
  flush                  : Flush all keys from the agent and records.
  list                   : List fingerprints of attached keys.
  keys                   : List public strings of attached keys.
  timeout <seconds>      : Update timeout for all recorded keys.
  cleanup                : Kill agent and remove session files.
  health                 : Check SSH environment health.
  version                : Display version information.

Arguments:
  key_file    Path to the SSH key file.
  seconds     New timeout in seconds (positive integer, max 86400).
EOF
    return "$exit_code"
}

dispatch() {
    local cmd=${1:-}
    if [[ -z "$cmd" ]]; then
        usage 1
        return 1
    fi
    shift

    case $cmd in
        # Key management
        attach | -a | --attach) attach "$@" ;;
        detach | -d | --detach) detach "$@" ;;
        flush | -f | --flush) flush "$@" ;;

        # Information/query
        list | -l | --list) list_keys "$@" ;;
        keys | -k | --keys) keys "$@" ;;

        # Configuration
        timeout | -t | --timeout) timeout "$@" ;;

        # Maintenance
        cleanup | -c | --cleanup) cleanup "$@" ;;
        health | -H | --health) health "$@" ;;

        # Meta
        version | -v | --version) version "$@" ;;
        help | -h | --help)
            usage 0
            return 0
            ;;

        *) error_exit "Unknown command: $cmd" ;;
    esac
}

########################################
# Main Execution
########################################

main() {
    validate_environment

    # Ensure agent is running/env is loaded for all commands that might need it.
    ensure_agent

    # Check if script is being sourced (setup aliases) or
    # executed (dispatch command)
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        # Script is being executed directly
        if [[ "${1:-}" == "health" ]] || [[ "${1:-}" == "list" ]] ||
            [[ "${1:-}" == "cleanup" ]] || [[ "${1:-}" == "keys" ]]; then
            # Allow informational/cleanup commands even if not sourced,
            # but warn that env changes won't persist.
            echo -e "\033[1;33mNote:\033[0m handsshake is a sub-process." >&2
            echo "Environment variables will not persist." >&2
        else
            echo -e "\033[1;31mWarning:\033[0m handsshake must be SOURCED." >&2
            echo "Usage: source $(basename "$0") <command>" >&2
            echo "Or alias: handsshake='source $(realpath "$0")'" >&2
        fi
        dispatch "$@"
    else
        # Script is sourced
        if [[ "$#" -gt 0 ]]; then
            dispatch "$@"
        fi
    fi
    return $?
}

run_with_lock "$HANDSSHAKE_LOCK_FILE" main "$@"
