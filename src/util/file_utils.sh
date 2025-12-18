set -euo pipefail

if [[ -n "${FILE_UTILS_LOADED:-}" ]]; then
    return 0
fi
readonly FILE_UTILS_LOADED=true

# Source logging utilities
source "$(dirname "${BASH_SOURCE[0]}")/logging_utils.sh"

# Helper Functions for File Operations

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

    validate_filepath_arg "$file" "secure_file: No file path provided." || return 1
    ensure_file_exists "$file" || return 1
    set_file_permissions "$file" || return 1

    return 0
}

atomic_write() {
    # Writes content to a file atomically.
    #
    # Args:
    #   file: (string) Path to the destination file.
    #   content: (string, optional) Content to write. If not provided, reads from stdin.
    # Returns:
    #   0 if successful, non-zero on failure.

    local file="$1"
    local temp_file

    validate_filepath_arg "$file" "atomic_write: No file path provided." || return 1

    temp_file="${file}.tmp.$$"

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
    #
    # Args:
    #   lock_file: (string) Path to the lock file.
    #   command: (string...) Command and arguments to execute.
    # Returns:
    #   Exit code of the command.
    local lock_file="$1"
    shift

    validate_filepath_arg "$lock_file" "run_with_lock: No lock file provided." || return 1
    ensure_file_exists "$lock_file" || return 1

    {
        flock -x 200 || { log_error "Failed to acquire lock on $lock_file."; return 1; }
        "$@"
    } 200>"$lock_file"
    return 0
}


