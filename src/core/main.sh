#!/usr/bin/env bash

# shellcheck shell=bash

########################################
# Global State & Pathing
########################################

# Prevent re-loading if this script is sourced multiple times
if [[ -z "${HANDSSHAKE_LOADED:-}" ]]; then
    HANDSSHAKE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    HANDSSHAKE_LOADED=true
fi

########################################
# Bootstrapping
########################################

# Source core utilities first (Manual bootstrapping)
# shellcheck source=/dev/null
source "$HANDSSHAKE_SCRIPT_DIR/../util/loggers.sh"
# shellcheck source=/dev/null
source "$HANDSSHAKE_SCRIPT_DIR/../util/files.sh"

# Use files::assert_source for the remaining modules
files::assert_source "$HANDSSHAKE_SCRIPT_DIR/../lib/constants.sh"
files::assert_source "$HANDSSHAKE_SCRIPT_DIR/../lib/configs.sh"
files::assert_source "$HANDSSHAKE_SCRIPT_DIR/../util/validators.sh"

# Load Configuration (XDG-aware)
configs::init

# Source Services
files::assert_source "$HANDSSHAKE_SCRIPT_DIR/../services/agents.sh"
files::assert_source "$HANDSSHAKE_SCRIPT_DIR/../services/keys.sh"
files::assert_source "$HANDSSHAKE_SCRIPT_DIR/../services/health.sh"

########################################
# Command Dispatch Module
########################################

usage() {
    local exit_code="${1:-0}"
    cat << EOF
Usage: source $(basename "$0") <command> [arguments]

Note: Commands marked with [S] must be run in a sourced shell to
      persist variables.
      Commands marked with [X] can be run directly as an executable.

Commands:
  attach [key_file] [S]  : Attach key to agent (default: ~/.ssh/id_ed25519).
  detach <key_file> [S]  : Detach a specific key from the agent.
  flush [S]              : Flush all keys from the agent and records.
  list [X]               : List fingerprints of attached keys.
  keys [X]               : List public strings of attached keys.
  timeout <key> <sec>    : Update/Set timeout for a specific key.
  timeout --all <sec>    : Update timeout for ALL recorded keys.
  cleanup [X]            : Kill agent and remove session files.
  health [X]             : Check SSH environment health.
  version [X]            : Display version information.

Arguments:
  key_file    Path to the SSH key file.
  seconds     New timeout in seconds (positive integer, max 86400).

Examples:
  source handsshake attach
  handsshake timeout ~/.ssh/id_rsa 3600
  handsshake timeout --all 7200
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
        # Key management (Requires Sourcing)
        attach | -a | --attach) keys::attach "$@" ;;
        detach | -d | --detach) keys::detach "$@" ;;
        flush | -f | --flush) keys::flush "$@" ;;

        # Information/query (Can run directly)
        list | -l | --list) keys::list "$@" ;;
        keys | -k | --keys) keys::show_public "$@" ;;

        # Configuration (Requires Sourcing)
        timeout | -t | --timeout)
            if [[ "$1" == "--all" ]]; then
                shift
                keys::update_all_timeouts "$@"
            else
                keys::update_timeout "$@"
            fi
            ;;

        # Maintenance
        cleanup | -c | --cleanup) agents::stop "$@" ;;
        health | -H | --health) health::check_all "$@" ;;

        # Meta
        version | -v | --version) agents::version "$@" ;;
        help | -h | --help)
            usage 0
            return 0
            ;;

        *)
            loggers::error_exit "Unknown command: $cmd"
            return 1
            ;;
    esac
}

########################################
# Main Execution
########################################

main() {
    # 1. Ensure all required system binaries exist
    if ! validators::environment; then
        return 1
    fi

    # 2. Ensure the agent context is available (starts or connects to agent)
    # Note: If executed directly, this agent process will become orphaned
    # unless 'cleanup' is called later. We mitigate this by blocking
    # state-changing commands in execution mode below.
    agents::ensure

    # 3. Determine Execution Context (Sourced vs. Executed)
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then

        ####################################################
        # SCENARIO: Script is EXECUTED directly (Subprocess)
        ####################################################

        # We strictly limit what commands can run in a subprocess to
        # prevent "Zombie Agents" and confusion about why variables
        # aren't set in the parent shell.

        local cmd="${1:-help}"

        case "$cmd" in
            health | list | keys | version | cleanup | help | -h | --help)
                # Read-only or self-destructive commands are safe
                dispatch "$@"
                ;;
            *)
                # State-changing commands are unsafe to run as a subprocess
                # because SSH_AUTH_SOCK will die when this script exits.
                local script_path="${BASH_SOURCE[0]}"
                local red="\033[1;31m"
                local yellow="\033[1;33m"
                local cyan="\033[1;36m"
                local nc="\033[0m" # No Color

                echo -e "${red}Error:${nc} Command '$cmd' requires shell \
integration." >&2
                echo -e "${yellow}Reason:${nc} Environment variables will \
not persist." >&2
                echo "" >&2
                echo "You must SOURCE this script to use this command:" >&2
                echo -e "  ${cyan}source $script_path $cmd $*${nc}" >&2
                echo "" >&2
                echo "Or create an alias in your .bashrc/.zshrc:" >&2
                echo -e "  ${cyan}alias handsshake='source $script_path'${nc}" \
                    >&2
                return 1
                ;;
        esac

    else

        ####################################################
        # SCENARIO: Script is SOURCED (Parent Shell)
        ####################################################

        if [[ "$#" -gt 0 ]]; then
            dispatch "$@"
        fi
    fi

    return $?
}

# Execute main with locking to prevent race conditions
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    files::run_with_lock "$HANDSSHAKE_LOCK_FILE" main "$@"
fi
