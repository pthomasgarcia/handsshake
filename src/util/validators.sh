# shellcheck shell=bash

if [[ -n "${HANDSSHAKE_VALIDATORS_LOADED:-}" ]]; then
    return 0
fi
HANDSSHAKE_VALIDATORS_LOADED=true

# Source logging utilities for consistent error reporting
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/loggers.sh"

# Source shared constants
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/constants.sh"

# Utility Functions

validators::trim_string() {
    # Validates that a string is non-empty after trimming whitespace.
    local var="$*"
    # Remove leading whitespace
    var="${var#"${var%%[![:space:]]*}"}"
    # Remove trailing whitespace
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
    return 0
}

validators::_log_error() {
    # Internal helper for logging validation errors
    if [[ "${HANDSSHAKE_VERBOSE:-false}" == "true" ]]; then
        loggers::error "$1: Input '$2'"
    fi
    return 0
}

validators::_validate_pattern() {
    # Internal generic pattern validator
    local trimmed
    trimmed=$(validators::trim_string "$1")

    if [[ -z "$trimmed" ]]; then
        validators::_log_error "$HANDSSHAKE_MESSAGE_EMPTY_STRING" "$1"
        return "$HANDSSHAKE_CODE_EMPTY_STRING"
    fi

    if [[ ! "$trimmed" =~ $2 ]]; then
        validators::_log_error "$4" "$1"
        return "$3"
    fi

    echo "$trimmed"
    return 0
}

# Core Data Validations

validators::string() {
    local trimmed
    trimmed=$(validators::trim_string "$1")

    if [[ -z "$trimmed" ]]; then
        validators::_log_error "$HANDSSHAKE_MESSAGE_EMPTY_STRING" "$1"
        return "$HANDSSHAKE_CODE_EMPTY_STRING"
    fi

    echo "$trimmed"
    return 0
}

validators::sanitize_string() {
    local input="$1"
    local sanitized
    sanitized="${input//[!a-zA-Z0-9 ,.;:_-]/}"
    echo "$sanitized"
}

validators::boolean() {
    local input
    input="${1:-}"
    local lower
    lower="${input,,}"

    validators::_validate_pattern "$lower" "$HANDSSHAKE_PATTERN_BOOL" \
        "$HANDSSHAKE_CODE_INVALID_BOOLEAN" "$HANDSSHAKE_MESSAGE_INVALID_BOOLEAN"
    return $?
}

validators::signed_integer() {
    validators::_validate_pattern "$1" "$HANDSSHAKE_PATTERN_INT" \
        "$HANDSSHAKE_CODE_INVALID_INTEGER" "$HANDSSHAKE_MESSAGE_INVALID_INTEGER"
    return $?
}

validators::signed_float() {
    validators::_validate_pattern "$1" "$HANDSSHAKE_PATTERN_FLOAT" \
        "$HANDSSHAKE_CODE_INVALID_FLOAT" "$HANDSSHAKE_MESSAGE_INVALID_FLOAT"
    return $?
}

# Numeric Constraints

validators::negative_allowed() {
    local integer
    local is_negative_allowed

    integer=$(validators::signed_integer "$1") || return $?
    is_negative_allowed=$(validators::boolean "${2:-true}") || return $?

    if [[ "$is_negative_allowed" == "false" && "$integer" -lt 0 ]]; then
        validators::_log_error "$HANDSSHAKE_MESSAGE_NEGATIVE_NOT_ALLOWED" "$1"
        return "$HANDSSHAKE_CODE_NEGATIVE_NOT_ALLOWED"
    fi
    return 0
}

validators::int64() {
    local integer
    local is_64bit_check_required

    integer="$1"
    is_64bit_check_required=$(validators::boolean "${2:-false}") || return $?

    if [[ "$is_64bit_check_required" == "true" ]]; then
        if ((integer < HANDSSHAKE_INT64_MIN || \
            integer > HANDSSHAKE_INT64_MAX)); then
            validators::_log_error "$HANDSSHAKE_MESSAGE_EXCEEDS_64BIT" \
                "$integer"
            return "$HANDSSHAKE_CODE_EXCEEDS_64BIT"
        fi
    fi
    return 0
}

validators::range() {
    local integer
    local min
    local max

    integer="$1"
    min="${2:-}"
    max="${3:-}"

    if [[ -n "$min" ]]; then
        min=$(validators::signed_integer "$min") || return $?
    fi
    if [[ -n "$max" ]]; then
        max=$(validators::signed_integer "$max") || return $?
    fi

    if [[ -n "$min" && "$integer" -lt "$min" ]]; then
        validators::_log_error "$HANDSSHAKE_MESSAGE_OUT_OF_RANGE: \
Value '$integer' is less than min '$min'" "$integer"
        return "$HANDSSHAKE_CODE_OUT_OF_RANGE"
    fi
    if [[ -n "$max" && "$integer" -gt "$max" ]]; then
        validators::_log_error "$HANDSSHAKE_MESSAGE_OUT_OF_RANGE: \
Value '$integer' is greater than max '$max'" "$integer"
        return "$HANDSSHAKE_CODE_OUT_OF_RANGE"
    fi
    return 0
}

validators::int_constraints() {
    local integer
    local min
    local max
    local is_negative_allowed
    local is_64bit_check_required

    integer="$1"
    min="${2:-}"
    max="${3:-}"
    is_negative_allowed="${4:-true}"
    is_64bit_check_required="${5:-false}"

    integer=$(validators::signed_integer "$integer") || return $?
    validators::negative_allowed "$integer" "$is_negative_allowed" || return $?
    validators::int64 "$integer" "$is_64bit_check_required" || return $?
    validators::range "$integer" "$min" "$max" || return $?

    return 0
}

# Identifier Validation

validators::identifier() {
    local identifier
    identifier=$(validators::_validate_pattern "$1" \
        "$HANDSSHAKE_PATTERN_IDENTIFIER" \
        "$HANDSSHAKE_CODE_INVALID_IDENTIFIER" \
        "$HANDSSHAKE_MESSAGE_INVALID_IDENTIFIER") || return $?

    if ! (declare -p "$identifier" &> /dev/null ||
        declare -F "$identifier" &> /dev/null); then
        validators::_log_error \
            "$HANDSSHAKE_MESSAGE_IDENTIFIER_UNDECLARED" "$identifier"
        return "$HANDSSHAKE_CODE_IDENTIFIER_UNDECLARED"
    fi

    echo "$identifier"
    return 0
}

# System State Checks

validators::file_exists() {
    # Checks if a file exists (Moved from loggers.sh)
    local file_path="$1"
    local error_message="${2:-"File not found: '$file_path'"}"

    if [[ -z "$file_path" ]]; then
        loggers::error "No file path provided for validators::file_exists."
        return 1
    fi

    if [[ ! -f "$file_path" ]]; then
        loggers::error "$error_message"
        return 1
    fi
    return 0
}

validators::directory() {
    local dir
    local is_writable_required

    dir=$(validators::trim_string "$1") || return $?
    is_writable_required=$(validators::boolean "${2:-false}") || return $?

    local resolved
    if ! resolved=$(realpath "$dir" 2> /dev/null) &&
        ! resolved=$(readlink -f "$dir" 2> /dev/null); then
        resolved="$dir"
    fi

    if [[ ! -d "$resolved" ]]; then
        validators::_log_error \
            "$HANDSSHAKE_MESSAGE_DIRECTORY_NOT_FOUND: Path '$dir'" "$dir"
        return "$HANDSSHAKE_CODE_DIRECTORY_NOT_FOUND"
    fi

    if [[ "$is_writable_required" == "true" && ! -w "$resolved" ]]; then
        validators::_log_error \
            "$HANDSSHAKE_MESSAGE_DIRECTORY_NOT_WRITABLE: Path '$dir'" "$dir"
        return "$HANDSSHAKE_CODE_DIRECTORY_NOT_WRITABLE"
    fi

    return 0
}

validators::ensure_directory() {
    # Note: Side effect - creates directory
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        if ! mkdir -p "$dir" 2> /dev/null; then
            validators::_log_error "Failed to create directory: '$dir'" "$dir"
            return "$HANDSSHAKE_CODE_FILE_PERMISSION"
        fi
    fi

    if ! validators::directory "$dir" "true"; then
        return $?
    fi

    return 0
}

validators::file() {
    local file
    local permission

    file=$(validators::trim_string "$1") || return $?
    permission=$(validators::trim_string "${2:-r}") || return $?

    if [[ ! -e "$file" ]]; then
        validators::_log_error \
            "$HANDSSHAKE_MESSAGE_FILE_NOT_FOUND: Path '$file'" "$file"
        return "$HANDSSHAKE_CODE_FILE_NOT_FOUND"
    fi

    if [[ "$permission" != "r" && "$permission" != "w" &&
        "$permission" != "x" ]]; then
        validators::_log_error "$HANDSSHAKE_MESSAGE_FILE_PERMISSION: \
Invalid permission mode '$permission'. Expected 'r', 'w', or 'x'." "$permission"
        return "$HANDSSHAKE_CODE_FILE_PERMISSION"
    fi

    case "$permission" in
        r) [[ -r "$file" ]] || {
            validators::_log_error \
                "$HANDSSHAKE_MESSAGE_FILE_PERMISSION: Read denied for '$file'" \
                "$file"
            return "$HANDSSHAKE_CODE_FILE_PERMISSION"
        } ;;
        w) [[ -w "$file" ]] || {
            validators::_log_error \
                "$HANDSSHAKE_MESSAGE_FILE_PERMISSION: Write denied \
for '$file'" \
                "$file"
            return "$HANDSSHAKE_CODE_FILE_PERMISSION"
        } ;;
        x) [[ -x "$file" ]] || {
            validators::_log_error \
                "$HANDSSHAKE_MESSAGE_FILE_PERMISSION: Execute \
denied for '$file'" \
                "$file"
            return "$HANDSSHAKE_CODE_FILE_PERMISSION"
        } ;;
    esac

    return 0
}

# Dependency Checks

validators::dependency() {
    local cmd="$1"
    if ! command -v "$cmd" > /dev/null 2>&1; then
        loggers::error_exit "Required command '$cmd' not found."
        return 1
    fi
    return 0
}

validators::environment() {
    local dependencies=(ssh-agent ssh-add awk pgrep kill flock)
    for dep in "${dependencies[@]}"; do
        if ! validators::dependency "$dep"; then
            return 1
        fi
    done
    return 0
}
