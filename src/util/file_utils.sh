# shellcheck shell=bash

if [[ -n "${HANDSSHAKE_FILE_UTILS_LOADED:-}" ]]; then
    return 0
fi
HANDSSHAKE_FILE_UTILS_LOADED=true

# Source logging utilities
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/logging_utils.sh"

# Helper Functions for File Operations

assert_source() {
    # Sources a file strictly, ensuring it is readable and non-empty.
    # Note: Depends on error_exit from logging_utils.sh.
    #
    # Args:
    #   file: (string) Path to the file to source.
    local file="$1"

    # 1. Check if file exists and is a regular file
    if [[ ! -f "$file" ]]; then
        error_exit "Source failed: '$file' does not exist or is not a file."
    fi

    # 2. Check if file is readable
    if [[ ! -r "$file" ]]; then
        error_exit "Source failed: '$file' is not readable (check permissions)."
    fi

    # 3. Check if file is non-empty (Size > 0)
    if [[ ! -s "$file" ]]; then
        error_exit "Source failed: '$file' is empty."
    fi

    # shellcheck source=/dev/null
    source "$file" || error_exit "Source failed: Error while executing '$file'."
}

validate_filepath_arg() {
    # Validates that a file path argument is provided and not empty.
    #
    # Args:
    #   file_path: (string) The file path to validate.
    #   error_message: (string) Custom error message if validation fails.
    # Returns:
    #   0 if valid, 1 if invalid.
    local file_path="$1"
    local error_message="${2:-"No file path provided."}"

    if [[ -z "$file_path" ]]; then
        log_error "$error_message"
        return 1
    fi
    return 0
}

set_file_permissions() {
    # Sets secure permissions (600) on a given file.
    #
    # Args:
    #   file: (string) Path to the file.
    # Returns:
    #   0 if successful, 1 on failure.
    local file="$1"
    if ! chmod 600 "$file"; then
        log_error "Failed to set permissions on $file."
        return 1
    fi
    return 0
}

ensure_file_exists() {
    # Ensures a file exists, creating it if necessary.
    #
    # Args:
    #   file: (string) Path to the file.
    # Returns:
    #   0 if successful, 1 on failure.
    local file="$1"
    if [[ ! -f "$file" ]]; then
        if ! touch "$file"; then
            log_error "Failed to create $file."
            return 1
        fi
    fi
    return 0
}

secure_file() {
    # Ensures a file exists and sets secure permissions.
    #
    # Args:
    #   file: (string) Path to the file to secure.
    # Returns:
    #   0 if successful, non-zero on failure.

    local file="$1"

    validate_filepath_arg "$file" \
        "secure_file: No file path provided." || return 1
    ensure_file_exists "$file" || return 1
    set_file_permissions "$file" || return 1

    return 0
}

atomic_write() {
    # Writes content to a file atomically.
    #
    # Args:
    #   file: (string) Path to the destination file.
    #   content: (string, optional) Content to write. If not provided,
    #            reads from stdin.
    # Returns:
    #   0 if successful, non-zero on failure.

    local file="$1"
    local temp_file

    validate_filepath_arg "$file" \
        "atomic_write: No file path provided." || return 1

    # Use mktemp to create a unique temporary file in the target directory
    # This ensures the atomic 'mv' works successfully (same filesystem).
    local dir
    local base
    dir=$(dirname "$file")
    base=$(basename "$file")

    if ! temp_file=$(mktemp -p "$dir" "${base}.XXXXXXXX"); then
        log_error "Failed to create temporary file for $file."
        return 1
    fi

    if [[ "$#" -ge 2 ]]; then
        echo "${2:-}" > "$temp_file"
    else
        cat > "$temp_file"
    fi

    if ! set_file_permissions "$temp_file"; then
        rm -f "$temp_file"
        return 1
    fi

    if ! mv "$temp_file" "$file"; then
        rm -f "$temp_file"
        log_error "Failed to move temporary file to $file."
        return 1
    fi

    return 0
}

run_with_lock() {
    # Executes a command with an exclusive lock.
    # Uses 'exec' for redirection to ensure environment variables set
    # by the command (like when sourcing an agent env) propagate to the parent.
    #
    # Args:
    #   lock_file: (string) Path to the lock file.
    #   command: (string...) Command and arguments to execute.
    # Returns:
    #   Exit code of the command.
    local lock_file="$1"
    shift

    validate_filepath_arg "$lock_file" \
        "run_with_lock: No lock file provided." || return 1
    ensure_file_exists "$lock_file" || return 1

    # Open lock file on FD 200
    exec 200> "$lock_file"

    # Acquire exclusive lock
    if ! flock -x 200; then
        log_error "Failed to acquire lock on $lock_file."
        exec 200>&-
        return 1
    fi

    # Execute command in the current shell context
    "$@"
    local ret=$?

    # Release lock and close FD
    flock -u 200
    exec 200>&-

    return "$ret"
}

parse_agent_env() {
    # Parses the SSH agent environment file and sets local variables.
    # Sets: __parsed_sock, __parsed_pid
    #
    # Args:
    #   env_file: (string) Path to the environment file.
    # Returns:
    #   0 if successful, non-zero if file missing or malformed.
    local env_file="$1"

    validate_filepath_arg "$env_file" \
        "parse_agent_env: No environment file path provided." || return 1

    if [[ ! -f "$env_file" ]]; then
        return 1
    fi

    __parsed_sock=$(sed -n 's/^SSH_AUTH_SOCK=//p' "$env_file")
    __parsed_pid=$(sed -n 's/^SSH_AGENT_PID=//p' "$env_file")

    if [[ -z "$__parsed_sock" ]] || [[ -z "$__parsed_pid" ]]; then
        return 1
    fi
    return 0
}
