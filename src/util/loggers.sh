# shellcheck shell=bash

if [[ -n "${HANDSSHAKE_LOGGERS_LOADED:-}" ]]; then
    return 0
fi
HANDSSHAKE_LOGGERS_LOADED=true

loggers::log_message() {
    # Internal: Logs a message to the console and a log file.
    local message="$1"
    local level="${2:-INFO}"
    local to_stderr="${3:-false}"
    local timestamp
    local formatted_message

    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    formatted_message="[$timestamp] [$level] $message"

    if [[ "${HANDSSHAKE_VERBOSE:-false}" == "true" ]]; then
        echo "$formatted_message"
    fi

    if [[ -n "${HANDSSHAKE_LOG_FILE:-}" ]]; then
        echo "$formatted_message" >> "$HANDSSHAKE_LOG_FILE"
    fi

    if [[ "$to_stderr" == "true" ]]; then
        echo "$formatted_message" >&2
    fi
    return 0
}

loggers::info() {
    loggers::log_message "$1" "INFO"
    return 0
}

loggers::warn() {
    loggers::log_message "$1" "WARN"
    return 0
}

loggers::error() {
    # Logs an error message and prints to stderr.
    loggers::log_message "$1" "ERROR" true
    return 0
}

loggers::critical() {
    # Logs a critical error message and prints to stderr.
    # User requested proper "critical" level in main.sh example.
    loggers::log_message "$1" "CRITICAL" true
    return 0
}

loggers::error_exit() {
    # Logs an error message and returns with a non-zero status.
    # Note: Uses return instead of exit to avoid terminating the shell
    # when sourced.
    local message="$1"
    local exit_code="${2:-1}"

    loggers::error "$message"
    return "$exit_code"
}
