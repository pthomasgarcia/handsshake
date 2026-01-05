#!/usr/bin/env bash
# src/core/main.sh
# shellcheck shell=bash

########################################
# Global State & Pathing
########################################

if [[ -z "${HANDSSHAKE_LOADED:-}" ]]; then
    HANDSSHAKE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    readonly HANDSSHAKE_SCRIPT_DIR
    readonly HANDSSHAKE_LOADED=true
fi

########################################
# Bootstrapping
########################################

# 1. Source core utilities first
# shellcheck source=/dev/null
source "$HANDSSHAKE_SCRIPT_DIR/../util/loggers.sh"
# shellcheck source=/dev/null
source "$HANDSSHAKE_SCRIPT_DIR/../util/files.sh"

# 2. Define remaining modules
files::assert_source "$HANDSSHAKE_SCRIPT_DIR/../lib/constants.sh"
files::assert_source "$HANDSSHAKE_SCRIPT_DIR/../lib/configs.sh"
files::assert_source "$HANDSSHAKE_SCRIPT_DIR/../util/validators.sh"
files::assert_source "$HANDSSHAKE_SCRIPT_DIR/../services/agents.sh"
files::assert_source "$HANDSSHAKE_SCRIPT_DIR/../services/keys.sh"
files::assert_source "$HANDSSHAKE_SCRIPT_DIR/../services/health.sh"

# 3. Load Configuration (Critical: establishes $HANDSSHAKE_LOCK_FILE)
configs::init

########################################
# UI Helpers
########################################

main::usage() {
    local exit_code="${1:-0}"
    cat << EOF
Usage: source $(basename "${BASH_SOURCE[-1]}") <command> [arguments]

Note: Commands marked with [S] must be run in a sourced shell to
      persist variables.
      Commands marked with [X] can be run directly as an executable.

Commands:
  attach [key_file] [S]  : Attach key to agent (default: ~/.ssh/id_ed25519).
  detach <key_file> [S]  : Detach a specific key from the agent.
  flush [S]              : Flush all keys from the agent and records.
  list [X]               : List fingerprints of attached keys.
  export [X]             : List public strings of attached keys.
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
EOF
    return "$exit_code"
}

########################################
# Command Dispatch Module
########################################

main::dispatch() {
    local cmd=${1:-}
    if [[ -z "$cmd" ]]; then
        main::usage 1
        return 1
    fi
    shift

    case $cmd in
        attach | -a | --attach) keys::attach "$@" || return ;;
        detach | -d | --detach) keys::detach "$@" || return ;;
        flush | -f | --flush) keys::flush "$@" || return ;;
        list | -l | --list) keys::list "$@" || return ;;
        export | -e | --export) keys::export "$@" || return ;;
        timeout | -t | '--timeout')
            if [[ "$1" == "--all" ]]; then
                shift
                keys::update_timeouts "$@" || return
            else
                keys::update_timeout "$@" || return
            fi
            ;;
        cleanup | -c | --cleanup) agents::stop "$@" || return ;;
        health | -H | --health) health::check_all "$@" || return ;;
        version | -v | --version) agents::version "$@" || return ;;
        help | -h | --help) main::usage 0 ;;
        *)
            loggers::error "Unknown command: $cmd"
            return 1
            ;;
    esac
}

########################################
# Main Execution Logic
########################################

# shellcheck disable=SC2120
# main() intentionally uses "$@" for argument passing
main() {
    # Debug validators status if DEBUG is set
    [[ "${DEBUG:-}" == "1" ]] && validators::debug_status

    # 1. Ensure all required system binaries exist
    if ! validators::environment; then
        return 1
    fi

    local cmd="${1:-help}"

    # 2. Validate command context compatibility
    if ! validators::command_context "$cmd"; then
        # Command requires sourcing but might not be sourced
        if ! validators::is_sourced; then
            validators::require_sourcing "$cmd"
            return 1
        fi
    fi

    # 3. Execute command
    if [[ "$#" -gt 0 ]]; then
        # REMOVED: agents::ensure from here
        main::dispatch "$@"
    else
        return 0
    fi
}

########################################
# Entry Point
########################################

# We lock if:
# 1. The script is being executed directly (always)
# 2. The script is sourced AND arguments are provided
if ! validators::is_sourced || [[ "$#" -gt 0 ]]; then
    files::lock "$HANDSSHAKE_LOCK_FILE" main "$@"
else
    # Sourced with no arguments: Just initialize environment
    main
fi
