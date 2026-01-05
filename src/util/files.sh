#!/usr/bin/env bash
# src/util/files.sh
# shellcheck shell=bash

if [[ -n "${HANDSSHAKE_FILES_LOADED:-}" ]]; then
    return 0
fi
HANDSSHAKE_FILES_LOADED=true

# Source logging utilities
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/loggers.sh"

# Helper Functions for File Operations

files::assert_source() {
    # Sources a file strictly, ensuring it is readable and non-empty.
    local file="$1"

    # 1. Check if file exists and is a regular file
    if [[ ! -f "$file" ]]; then
        loggers::error_exit "Source failed: '$file' does not exist or is \
not a file."
    fi

    # 2. Check if file is readable
    if [[ ! -r "$file" ]]; then
        loggers::error_exit "Source failed: '$file' is not readable \
(check permissions)."
    fi

    local _prev_set_e_=""
    if [[ -o errexit ]]; then
        _prev_set_e_="true"
        set +e
    fi

    # 3. Check if file is non-empty (Size > 0)
    if [[ ! -s "$file" ]]; then
        loggers::error_exit "Source failed: '$file' is empty."
    fi

    # shellcheck source=/dev/null
    source "$file" || loggers::error_exit "Source failed: Error while \
executing '$file'."
}

files::validate_path() {
    # Internal: Validates that a file path argument is provided and not empty.
    local file_path="$1"
    local error_message="${2:-"No file path provided."}"

    if [[ -z "$file_path" ]]; then
        loggers::error "$error_message"
        return 1
    fi
    return 0
}

files::set_permissions() {
    # Sets secure permissions (600) on a given file.
    local file="$1"
    if ! chmod 600 "$file"; then
        loggers::error "Failed to set permissions on $file."
        return 1
    fi
    return 0
}

files::ensure_exists() {
    # Ensures a file exists, creating it if necessary.
    local file="$1"
    if [[ ! -f "$file" ]]; then
        if ! touch "$file"; then
            loggers::error "Failed to create $file."
            return 1
        fi
    fi
    return 0
}

files::secure() {
    # Ensures a file exists and sets secure permissions.
    local file="$1"

    files::validate_path "$file" \
        "files::secure: No file path provided." || return 1
    files::ensure_exists "$file" || return 1
    files::set_permissions "$file" || return 1

    return 0
}

files::atomic_write() {
    # Writes content to a file atomically.
    local file="$1"
    local temp_file

    files::validate_path "$file" \
        "files::atomic_write: No file path provided." || return 1

    # Use mktemp to create a unique temporary file in the target directory
    local dir
    local base
    dir=$(dirname "$file")
    base=$(basename "$file")

    if ! temp_file=$(mktemp -p "$dir" "${base}.XXXXXXXX"); then
        loggers::error "Failed to create temporary file for $file."
        return 1
    fi

    if [[ "$#" -ge 2 ]]; then
        echo "${2:-}" > "$temp_file"
    else
        cat > "$temp_file"
    fi

    if ! files::set_permissions "$temp_file"; then
        rm -f "$temp_file"
        return 1
    fi

    if ! mv "$temp_file" "$file"; then
        rm -f "$temp_file"
        loggers::error "Failed to move temporary file to $file."
        return 1
    fi

    return 0
}

files::lock() {
    local file="$1"
    shift
    local cmd=("$@")

    files::validate_path "$file" \
        "files::lock: No file provided." || return 1

    files::ensure_exists "$file" || return 1

    # Open lock file on FD 200
    exec 200>> "$file"

    if ! flock -x 200; then
        local lock_holder
        lock_holder=$(fuser "$file" 2> /dev/null || echo "unknown")
        loggers::error "Failed to acquire lock on $file (held by: $lock_holder)"
        exec 200>&-
        return 1
    fi

    # Execute command in current shell context
    "${cmd[@]}"
    local ret=$?

    # Release lock and close FD
    flock -u 200
    exec 200>&-

    return $ret
}

files::parse_agent_env() {
    # Parses the SSH agent environment file and sets local variables.
    local env_file="$1"

    files::validate_path "$env_file" \
        "files::parse_agent_env: No environment file path provided." || return 1

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
