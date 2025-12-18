set -euo pipefail

if [[ -n "${LOGGING_UTILS_LOADED:-}" ]]; then
    return 0
fi
readonly LOGGING_UTILS_LOADED=true

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
    
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo "$formatted_message"
    fi
    echo "$formatted_message" >> "$LOG_FILE"

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
    exit "$exit_code"
}

