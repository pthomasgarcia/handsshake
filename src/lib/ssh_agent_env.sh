# shellcheck shell=bash
set -euo pipefail

# Define constants
# Source shared constants
source "$(dirname "${BASH_SOURCE[0]}")/constants.sh"

is_socket_present() {
    # Checks if a given socket path exists and is a valid socket.
    #
    # Arguments:
    #   socket: (string) The socket path to validate.
    #
    # Returns:
    #   0 if the socket exists and is a socket.
    #   CODE_INVALID_SOCKET if the socket does not exist or is not a socket.

    local socket

    # Validate input string
    socket=$(validate_string "$1") || return "$CODE_EMPTY_STRING"

    # Ensure the file exists and is a socket
    if [[ ! -S "$socket" ]]; then
        return "$CODE_INVALID_SOCKET"
    fi

    return 0
}

is_process_running() {
    # Checks if a process with the given PID is running and matches the expected name.
    #
    # Arguments:
    #   pid: (integer) The process ID (PID) to check.
    #   expected_process (string) The expected process name.
    #
    # Returns:
    #   0 if the process is running and matches the expected name.
    #   CODE_PROCESS_NOT_RUNNING if the process is not running or does not match.
    #   CODE_INVALID_INTEGER if the PID is not a valid integer.
    #   CODE_EMPTY_STRING if the expected process name is empty.

    local pid
    local expected_process
    local found_process

    pid="$(validate_signed_integer "$1")" || return "$CODE_INVALID_INTEGER"
    expected_process="$(validate_string "$2")" || return "$CODE_EMPTY_STRING"

    # Get process name using `ps` and extract basename
    if ! command -v ps >/dev/null 2>&1; then
        return "$CODE_PROCESS_NOT_RUNNING"
    fi

    found_process="$(ps -p "$pid" -o comm= 2>/dev/null)" || return "$CODE_PROCESS_NOT_RUNNING"
    found_process="$(basename "$found_process")"  # Handle paths in process names

    found_process="$(validate_string "$found_process")" || return "$CODE_PROCESS_NOT_RUNNING"

    # Validate the process name matches the expected one
    if [[ "$found_process" != "$expected_process" ]]; then
        return "$CODE_PROCESS_NOT_RUNNING"
    fi

    return 0
}

validate_agent_env() {
    # Ensures the SSH agent environment is valid and running.
    #
    # Arguments:
    #   file: (string) The path to the SSH agent environment file.
    #   expected_process: (string) The expected SSH agent process name.
    #
    # Returns:
    #   0 if the SSH agent environment is valid.
    #   CODE_FILE_NOT_FOUND if the agent environment file is missing.
    #   CODE_INVALID_ENV if the environment file is malformed or missing values.
    #   CODE_INVALID_SOCKET if SSH_AUTH_SOCK is invalid.
    #   CODE_PROCESS_NOT_RUNNING if the agent process is not running.

    local file="$1"
    local expected_process="$2"
    local socket
    local pid

    validate_file "$file" "r" || return $?

    # Safer environment variable parsing without sourcing
    if ! command -v grep >/dev/null 2>&1; then
        return "$CODE_INVALID_ENV"
    fi

    socket=$(grep -oP 'SSH_AUTH_SOCK=\K[^ ]+' "$file" 2>/dev/null) || true
    pid=$(grep -oP 'SSH_AGENT_PID=\K[^ ]+' "$file" 2>/dev/null) || true

    if [[ -z "$socket" ]]; then
        return "$CODE_INVALID_ENV"
    fi
    if [[ -z "$pid" ]]; then
        return "$CODE_INVALID_ENV"
    fi

    # Validate parsed values
    socket="$(validate_string "$socket")" || return $CODE_INVALID_ENV
    pid="$(validate_signed_integer "$pid")" || return $CODE_INVALID_ENV

    is_socket_present "$socket" || return $CODE_INVALID_SOCKET
    is_process_running "$pid" "$expected_process" || return $CODE_PROCESS_NOT_RUNNING

    return 0
}

write_agent_env() {
    # Writes the provided SSH agent environment variables to a specified file.
    #
    # Arguments:
    #   socket: (string) The SSH_AUTH_SOCK value to write.
    #   pid: (integer) The SSH_AGENT_PID value to write.
    #   file: (string) The path to the agent environment file.
    #
    # Returns:
    #   0 if the environment file is successfully written.
    #   CODE_EMPTY_STRING if SSH_AUTH_SOCK is empty.
    #   CODE_INVALID_INTEGER if SSH_AGENT_PID is not a valid integer.
    #   CODE_FILE_PERMISSION if the file cannot be created or modified.

    local socket="$1"
    local pid="$2"
    local file="$3"

    # Validate inputs
    validate_string "$socket" || return $?
    validate_signed_integer "$pid" || return $?
    validate_string "$file" || return $?

    # Ensure file is writable/creatable
    validate_file "$file" "w" || return "$CODE_FILE_PERMISSION"

    # Write environment variables to the file
    {
        echo "export SSH_AUTH_SOCK=$socket"
        echo "export SSH_AGENT_PID=$pid"
    } > "$file" || return $CODE_FILE_PERMISSION

    chmod 600 "$file" || return $CODE_FILE_PERMISSION

    log_action "Updated ssh-agent environment file: $file"
    return 0
}

setup_agent_env() {
    # Ensures the directory exists and writes the SSH agent environment variables to a file.
    #
    # Arguments:
    #   socket: (string) The SSH_AUTH_SOCK value to write.
    #   pid: (integer) The SSH_AGENT_PID value to write.
    #   file: (string) The path to the agent environment file.
    #
    # Returns:
    #   0 if the environment file is successfully written.
    #   CODE_EMPTY_STRING if SSH_AUTH_SOCK or file path is empty.
    #   CODE_INVALID_INTEGER if SSH_AGENT_PID is not a valid integer.
    #   CODE_FILE_PERMISSION if the directory or file cannot be created or modified.

    local socket="$1"
    local pid="$2"
    local file="$3"
    local dir

    # Extract directory from file path
    dir="$(dirname "$file")"

    # Ensure directory exists and is writable
    ensure_directory "$dir" || {
        handle_error "$?" "Failed to create or validate directory: $dir"
        return $?
    }

    # Write environment variables to the file
    write_agent_env "$socket" "$pid" "$file" || {
        handle_error "$?" "Failed to write environment variables to file: $file"
        return $?
    }

    return 0
}
