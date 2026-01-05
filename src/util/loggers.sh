#!/usr/bin/env bash
# src/util/loggers.sh
# shellcheck shell=bash

if [[ -n "${HANDSSHAKE_LOGGERS_LOADED:-}" ]]; then
    return 0
fi
HANDSSHAKE_LOGGERS_LOADED=true

# --- UI Formatting ---

declare -gA _LOG_COLORS=(
    [error]="${FMT_RED:-}"
    [warning]="${FMT_YELLOW:-}"
    [info]="${FMT_CYAN:-}"
)

loggers::format() {
    # Description: Prints a colored, formatted message to the terminal.
    # Args: $1: type (error|warning|info), $2: message text
    local type="$1"
    local message="$2"
    local color="${_LOG_COLORS[$type]:-}"

    # Optimization: printf is more robust than echo -e for variable input
    printf "%b%s:%b %s\n" "$color" "${type^}" "${FMT_RESET:-}" "$message" >&2
}

# --- Internal Logging Logic ---

loggers::log_message() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp
    local formatted_message

    # Optimization: Bash 4.2+ native timestamp (avoids forking a 'date' process)
    printf -v timestamp '%(%Y-%m-%d %H:%M:%S)T' -1
    formatted_message="[$timestamp] [$level] $message"

    # 1. Handle Verbose Console Output (Plain text for logs)
    if [[ "${HANDSSHAKE_VERBOSE:-false}" == "true" ]]; then
        printf "%s\n" "$formatted_message" >&2
    fi

    # 2. Handle File Logging (Never contains ANSI colors)
    if [[ -n "${HANDSSHAKE_LOG_FILE:-}" ]]; then
        printf "%s\n" "$formatted_message" >> "$HANDSSHAKE_LOG_FILE"
    fi
}

# --- Public API ---

loggers::info() {
    loggers::format "info" "$1"
    loggers::log_message "$1" "INFO"
}

loggers::warn() {
    loggers::format "warning" "$1"
    loggers::log_message "$1" "WARN"
}

loggers::error() {
    loggers::format "error" "$1"
    loggers::log_message "$1" "ERROR"
}

loggers::critical() {
    loggers::format "error" "$1"
    loggers::log_message "$1" "CRITICAL"
}

loggers::error_exit() {
    local message="$1"
    local exit_code="${2:-1}"
    loggers::error "$message"
    return "$exit_code"
}
