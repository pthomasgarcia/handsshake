#!/usr/bin/env bash
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

__handsshake_usage() {
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
EOF
    return "$exit_code"
}

print_fmt() {
    local fmt
    case "$1" in
        error) fmt="${FMT_RED:-}" ;;
        warning) fmt="${FMT_YELLOW:-}" ;;
        info) fmt="${FMT_CYAN:-}" ;;
        *) fmt="" ;;
    esac
    echo -e "${fmt}${1^}:${FMT_RESET:-} $2" >&2
}

report_usage_error() {
    # Reports why a command failed when run in a subshell.
    local cmd="$1"
    local user_rc=".${SHELL##*/:-bash}rc"
    # Use BASH_SOURCE[-1] to get the entry-point script path
    local script_path="${BASH_SOURCE[-1]}"

    print_fmt error "Command '$cmd' requires shell integration"
    print_fmt warning "Environment variables (like SSH_AUTH_SOCK) will not"
    print_fmt warning "persist in subshells."
    echo >&2

    print_fmt info "Fix: source $script_path $*"
    print_fmt info "Or add this alias to ~/$user_rc:"
    echo -e "  ${FMT_CYAN:-}alias handsshake=" \
        "'source $script_path'${FMT_RESET:-}" >&2

    return 1
}

########################################
# Command Dispatch Module
########################################

dispatch() {
    local cmd=${1:-}
    if [[ -z "$cmd" ]]; then
        __handsshake_usage 1
        return 1
    fi
    shift

    case $cmd in
        attach | -a | --attach) keys::attach "$@" ;;
        detach | -d | --detach) keys::detach "$@" ;;
        flush | -f | --flush) keys::flush "$@" ;;
        list | -l | --list) keys::list "$@" ;;
        keys | -k | --keys) keys::show_public "$@" ;;
        timeout | -t | --timeout)
            if [[ "$1" == "--all" ]]; then
                shift
                keys::update_all_timeouts "$@"
            else
                keys::update_timeout "$@"
            fi
            ;;
        cleanup | -c | --cleanup) agents::stop "$@" ;;
        health | -H | --health) health::check_all "$@" ;;
        version | -v | --version) agents::version "$@" ;;
        help | -h | --help) __handsshake_usage 0 ;;
        *)
            loggers::error "Unknown command: $cmd"
            return 1
            ;;
    esac
}

########################################
# Main Execution Logic
########################################

main() {
    # 1. Ensure all required system binaries exist
    if ! validators::environment; then
        return 1
    fi

    local cmd="${1:-help}"

    # 2. Determine Execution Context
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        # SCENARIO: Script is EXECUTED directly
        set -Euo pipefail

        case "$cmd" in
            health | list | keys | version | cleanup | help | -h | --help)
                agents::ensure
                dispatch "$@"
                ;;
            *)
                report_usage_error "$@"
                return 1
                ;;
        esac
    else
        # SCENARIO: Script is SOURCED
        if [[ "$#" -gt 0 ]]; then
            agents::ensure
            dispatch "$@"
        else
            return 0
        fi
    fi
}

########################################
# Entry Point
########################################

# We lock if:
# 1. The script is being executed directly (always)
# 2. The script is sourced AND arguments are provided
if [[ "${BASH_SOURCE[0]}" == "${0}" || "$#" -gt 0 ]]; then
    files::run_with_lock "$HANDSSHAKE_LOCK_FILE" main "$@"
else
    # Sourced with no arguments: Just initialize environment
    main
fi
