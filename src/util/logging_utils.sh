# shellcheck shell=bash

if [[ -n "${HANDSSHAKE_LOGGING_UTILS_LOADED:-}" ]]; then
    return 0
fi
HANDSSHAKE_LOGGING_UTILS_LOADED=true

log_message() {
    # Logs a message to the console and a log file.
    #
    # Args:
    #   message: (string) The message to log.
    #   level: (string, optional) The log level (e.g., INFO, ERROR). Defaults to INFO.
    #   to_stderr: (boolean, optional) If true, also prints to stderr. Defaults to false.
    # Returns:
    #   None

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

check_file_exists() {
    # Checks if a file exists and logs an error if it doesn't.
    #
    # Args:
    #   file_path: (string) The path to the file to check.
    #   error_message: (string, optional) Custom error message if file is missing.
    # Returns:
    #   0 if file exists, 1 otherwise.
    local file_path="$1"
    local error_message="${2:-"File not found: '$file_path'"}"

    if [[ -z "$file_path" ]]; then
        log_error "No file path provided for check_file_exists."
        return 1
    fi

    if [[ ! -f "$file_path" ]]; then
        log_error "$error_message"
        return 1
    fi
    return 0
}

log_info() {
    # Logs an informational message.
    #
    # Args:
    #   message: (string) The message to log.
    log_message "$1" "INFO"
    return 0
}

log_error() {
    # Logs an error message and prints to stderr.
    #
    # Args:
    #   message: (string) The error message to log.
    log_message "$1" "ERROR" true
    return 0
}

error_exit_with_log() {
    # Logs an error message and exits the script with a non-zero status.
    #
    # Args:
    #   message: (string) The error message to log and display before exiting.
    #   exit_code: (int, optional) The exit code. Defaults to 1.
    
    local message="$1"
    local exit_code="${2:-1}"

    log_error "$message"
    # Use return instead of exit to avoid killing the shell when sourced
    return "$exit_code"
}

error_exit() {
    # Public wrapper for error_exit_with_log.
    # Logs an error message and returns with a non-zero status.
    # Note: Uses return instead of exit to avoid terminating the shell when sourced.
    # Callers should check the return value and handle termination as needed.
    #
    # Args:
    #   message: (string) The error message to log and display.
    #   exit_code: (int, optional) The return code. Defaults to 1.
    # Returns:
    #   The specified exit_code (or 1 by default).
    error_exit_with_log "$@"
}

