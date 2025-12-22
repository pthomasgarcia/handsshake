# shellcheck shell=bash

if [[ -n "${HANDSSHAKE_VALIDATION_UTILS_LOADED:-}" ]]; then
    return 0
fi
HANDSSHAKE_VALIDATION_UTILS_LOADED=true

# Source logging utilities for consistent error reporting
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/logging_utils.sh"

# Source shared constants
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/constants.sh"

# Utility Functions

trim_string() {
    # Validates that a string is non-empty after trimming whitespace.
    # Uses native Bash parameter expansion for efficiency.
    #
    # Arguments:
    #   string: (string) The input string to trim.
    #
    # Returns:
    #   (string) The trimmed string.

    local var="$*"
    # Remove leading whitespace
    var="${var#"${var%%[![:space:]]*}"}"
    # Remove trailing whitespace
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
    return 0
}

_log_validation_error() {
    # Internal helper for logging validation errors if
    # HANDSSHAKE_VERBOSE is true.
    #
    # Arguments:
    #   message: (string) The error message.
    #   input: (string) The original invalid input.

    if [[ "${HANDSSHAKE_VERBOSE:-false}" == "true" ]]; then
        log_error "$1: Input '$2'"
    fi
    return 0
}

_validate_pattern() {
    # Internal generic pattern validator to reduce duplication.
    #
    # Arguments:
    #   input: (string) The value to validate.
    #   pattern: (string) The regex pattern to match against.
    #   error_code: (int) The error code to return on failure.
    #   error_message: (string) The error message to log on failure.
    #
    # Returns:
    #   (string) The trimmed and validated string on success.
    #   Exit code on failure.

    local trimmed
    trimmed=$(trim_string "$1")

    if [[ -z "$trimmed" ]]; then
        _log_validation_error "$HANDSSHAKE_MESSAGE_EMPTY_STRING" "$1"
        return "$HANDSSHAKE_CODE_EMPTY_STRING"
    fi

    if [[ ! "$trimmed" =~ $2 ]]; then
        _log_validation_error "$4" "$1"
        return "$3"
    fi

    echo "$trimmed"
    return 0
}

# Core Data Validations

validate_string() {
    # Validates that a string is non-empty after trimming whitespace.
    #
    # Arguments:
    #   string: (string) The input string to validate.
    #
    # Returns:
    #   (string) The trimmed string if valid.
    #
    # Errors:
    #   CODE_EMPTY_STRING: The input string is empty after trimming
    #                      or is invalid.

    local trimmed
    trimmed=$(trim_string "$1")

    if [[ -z "$trimmed" ]]; then
        _log_validation_error "$HANDSSHAKE_MESSAGE_EMPTY_STRING" "$1"
        return "$HANDSSHAKE_CODE_EMPTY_STRING"
    fi

    echo "$trimmed"
    return 0
}

sanitize_string() {
    local input="$1"

    # Remove any character that is not a letter, number, space,
    # or basic punctuation.
    # The pattern [!a-zA-Z0-9 ,.;:_-] matches any character not in the list.
    local sanitized
    sanitized="${input//[!a-zA-Z0-9 ,.;:_-]/}"

    echo "$sanitized"
}

validate_boolean() {
    # Validates whether the input is 'true' or 'false' (case-insensitive).
    #
    # Arguments:
    #   boolean: (string) The value to validate.
    #
    # Returns:
    #   (string) 'true' or 'false' if valid, in lowercase.
    #   Exit code on failure.

    local input
    input="${1:-}"

    # Convert to lowercase for case-insensitive comparison
    local lower
    lower="${input,,}"

    _validate_pattern "$lower" "$HANDSSHAKE_PATTERN_BOOL" \
        "$HANDSSHAKE_CODE_INVALID_BOOLEAN" "$HANDSSHAKE_MESSAGE_INVALID_BOOLEAN"
    return $?
}

validate_signed_integer() {
    # Validates whether the given value is a signed integer
    # (positive or negative).
    #
    # Arguments:
    #   integer: (string) The value to validate.
    #
    # Returns:
    #   (string) The validated integer if valid.
    #   Exit code on failure.

    _validate_pattern "$1" "$HANDSSHAKE_PATTERN_INT" \
        "$HANDSSHAKE_CODE_INVALID_INTEGER" "$HANDSSHAKE_MESSAGE_INVALID_INTEGER"
    return $?
}

validate_signed_float() {
    # Validates whether the given value is a signed floating-point number.
    #
    # Arguments:
    #   float: (string) The value to validate.
    #
    # Returns:
    #   (string) The validated float if valid.
    #   Exit code on failure.

    _validate_pattern "$1" "$HANDSSHAKE_PATTERN_FLOAT" \
        "$HANDSSHAKE_CODE_INVALID_FLOAT" "$HANDSSHAKE_MESSAGE_INVALID_FLOAT"
    return $?
}

# Numeric Constraints

validate_negative_allowed() {
    # Validates whether negative values are allowed for the given value.
    #
    # Arguments:
    #   integer: (numeric) The value to validate.
    #   is_negative_allowed: (string, optional) 'true' or 'false',
    #                        case-insensitive. Defaults to 'true'.
    #
    # Returns:
    #   0 if valid.
    #   Exit code on failure.

    local integer
    local is_negative_allowed

    integer=$(validate_signed_integer "$1") || return $?
    is_negative_allowed=$(validate_boolean "${2:-true}") || return $?

    if [[ "$is_negative_allowed" == "false" && "$integer" -lt 0 ]]; then
        _log_validation_error "$HANDSSHAKE_MESSAGE_NEGATIVE_NOT_ALLOWED" "$1"
        return "$HANDSSHAKE_CODE_NEGATIVE_NOT_ALLOWED"
    fi

    return 0
}

validate_64bit_integer() {
    # Validates whether the value fits within 64-bit signed integer limits.
    #
    # Arguments:
    #   integer": (numeric) A validated in"teger.
    #   is_64bit_check_required: (string) 'true' or 'false'.
    #
    # Returns:
    #   0 if the value is within limits.
    #   Exit code on failure.

    local integer
    local is_64bit_check_required

    integer="$1"
    is_64bit_check_required=$(validate_boolean "${2:-false}") || return $?

    # Ensure that the check only runs if explicitly required
    if [[ "$is_64bit_check_required" == "true" ]]; then
        if ((integer < HANDSSHAKE_INT64_MIN || \
            integer > HANDSSHAKE_INT64_MAX)); then
            _log_validation_error "$HANDSSHAKE_MESSAGE_EXCEEDS_64BIT" "$integer"
            return "$HANDSSHAKE_CODE_EXCEEDS_64BIT"
        fi
    fi

    return 0
}

validate_range() {
    # Validates whether a value is within a specified numeric range.
    #
    # Arguments:
    #   integer: (numeric) The value to validate.
    #   min: (numeric, optional) Minimum allowed value.
    #   max: (numeric, optional) Maximum allowed value.
    #
    # Returns:
    #   0 if the value is within range.
    #   Exit code on failure.

    local integer
    local min
    local max

    integer="$1"
    min="${2:-}"
    max="${3:-}"

    # Validate min and max if provided
    if [[ -n "$min" ]]; then
        min=$(validate_signed_integer "$min") || return $?
    fi
    if [[ -n "$max" ]]; then
        max=$(validate_signed_integer "$max") || return $?
    fi

    # Check if the value is within the range
    if [[ -n "$min" && "$integer" -lt "$min" ]]; then
        _log_validation_error "$HANDSSHAKE_MESSAGE_OUT_OF_RANGE: \
Value '$integer' is less than min '$min'" "$integer"
        return "$HANDSSHAKE_CODE_OUT_OF_RANGE"
    fi
    if [[ -n "$max" && "$integer" -gt "$max" ]]; then
        _log_validation_error "$HANDSSHAKE_MESSAGE_OUT_OF_RANGE: \
Value '$integer' is greater than max '$max'" "$integer"
        return "$HANDSSHAKE_CODE_OUT_OF_RANGE"
    fi

    return 0
}

validate_integer_constraints() {
    # Validates an integer against constraints like negatives,
    # 64-bit, and range limits.
    #
    # Arguments:
    #   integer": (numeric) The va"lue to validate.
    #   min: (numeric, optional) Minimum allowed value.
    #   max: (numeric, optional) Maximum allowed value.
    #   is_negative_allowed: (string, optional) 'true' or 'false'.
    #                        Defaults to 'true'.
    #   is_64bit_check_required: (string, optional) 'true' or 'false'.
    #                            Defaults to 'false'.
    #
    # Returns:
    #   0 if valid.
    #   Exit code on failure.

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

    # Validate the integer (ensuring it's actually a number)
    integer=$(validate_signed_integer "$integer") || return $?

    # Check for negative allowance
    validate_negative_allowed "$integer" "$is_negative_allowed" || return $?

    # Validate 64-bit constraints only if required
    validate_64bit_integer "$integer" "$is_64bit_check_required" || return $?

    # Pass validated min/max to validate_range
    validate_range "$integer" "$min" "$max" || return $?

    return 0
}

# Identifier Validation

validate_identifier() {
    # Validates whether the provided identifier is valid, declared,
    # and non-empty.
    #
    # Arguments:
    #   identifier: (string) The name of the identifier to validate.
    #
    # Returns:
    #   (string) The validated identifier name if valid.
    #   Exit code on failure.

    local identifier
    identifier=$(_validate_pattern "$1" "$HANDSSHAKE_PATTERN_IDENTIFIER" \
        "$HANDSSHAKE_CODE_INVALID_IDENTIFIER" \
        "$HANDSSHAKE_MESSAGE_INVALID_IDENTIFIER") || return $?

    # Check if the identifier is declared (as a variable or function)
    if ! (declare -p "$identifier" &> /dev/null ||
        declare -F "$identifier" &> /dev/null); then
        _log_validation_error \
            "$HANDSSHAKE_MESSAGE_IDENTIFIER_UNDECLARED" "$identifier"
        return "$HANDSSHAKE_CODE_IDENTIFIER_UNDECLARED"
    fi

    echo "$identifier"
    return 0
}

# System State Checks

validate_directory() {
    # Validates whether the specified directory exists and,
    # if required, is writable.
    #
    # Arguments:
    #   dir: (string) The path to the directory to validate.
    #   is_writable_required: (string, optional) 'true' to check
    #                          if writable. Defaults to 'false'.
    #
    # Returns:
    #   0 if the directory exists and meets writability requirements.
    #   Exit code on failure.

    local dir
    local is_writable_required

    dir=$(trim_string "$1") || return $?
    is_writable_required=$(validate_boolean "${2:-false}") || return $?

    # Resolve the directory path to an absolute path
    local resolved
    if ! resolved=$(realpath "$dir" 2> /dev/null) &&
        ! resolved=$(readlink -f "$dir" 2> /dev/null); then
        resolved="$dir" # Fallback to the original path
    fi

    if [[ ! -d "$resolved" ]]; then
        _log_validation_error \
            "$HANDSSHAKE_MESSAGE_DIRECTORY_NOT_FOUND: Path '$dir'" "$dir"
        return "$HANDSSHAKE_CODE_DIRECTORY_NOT_FOUND"
    fi

    if [[ "$is_writable_required" == "true" && ! -w "$resolved" ]]; then
        _log_validation_error \
            "$HANDSSHAKE_MESSAGE_DIRECTORY_NOT_WRITABLE: Path '$dir'" "$dir"
        return "$HANDSSHAKE_CODE_DIRECTORY_NOT_WRITABLE"
    fi

    return 0
}

ensure_directory() {
    # Ensures the specified directory exists and is writable.
    # Note: This function HAS the side effect of creating the directory.
    #
    # Arguments":"
    #   dir: (string) The directory path to validate or create.
    #
    # Returns:
    #   0 if the directory exists/was created and is writable.
    #   CODE_FILE_PERMISSION if it cannot be created or is not writable.

    local dir="$1"

    # Check existence silently first to avoid noisy logs during initialization
    if [[ ! -d "$dir" ]]; then
        if ! mkdir -p "$dir" 2> /dev/null; then
            _log_validation_error "Failed to create directory: '$dir'" "$dir"
            return "$HANDSSHAKE_CODE_FILE_PERMISSION"
        fi
    fi

    # Now validate it properly (writability, etc.)
    if ! validate_directory "$dir" "true"; then
        return $?
    fi

    return 0
}

validate_file() {
    # Validates whether the specified file exists and has the
    # required permissions.
    #
    # Arguments:
    #   file: (string) The path to the file to validate.
    #   permission: (string, optional) 'r', 'w', or 'x'. Defaults to 'r'.
    #
    # Returns:
    #   0 if the file exists and meets the required permissions.
    #   Exit code on failure.

    local file
    local permission

    file=$(trim_string "$1") || return $?
    permission=$(trim_string "${2:-r}") || return $?

    if [[ ! -e "$file" ]]; then
        _log_validation_error \
            "$HANDSSHAKE_MESSAGE_FILE_NOT_FOUND: Path '$file'" "$file"
        return "$HANDSSHAKE_CODE_FILE_NOT_FOUND"
    fi

    if [[ "$permission" != "r" && "$permission" != "w" &&
        "$permission" != "x" ]]; then
        _log_validation_error "$HANDSSHAKE_MESSAGE_FILE_PERMISSION: \
Invalid permission mode '$permission'. Expected 'r', 'w', or 'x'." "$permission"
        return "$HANDSSHAKE_CODE_FILE_PERMISSION"
    fi

    case "$permission" in
        r) [[ -r "$file" ]] || {
            _log_validation_error \
                "$HANDSSHAKE_MESSAGE_FILE_PERMISSION: Read denied for '$file'" \
                "$file"
            return "$HANDSSHAKE_CODE_FILE_PERMISSION"
        } ;;
        w) [[ -w "$file" ]] || {
            _log_validation_error \
                "$HANDSSHAKE_MESSAGE_FILE_PERMISSION: Write denied \
for '$file'" \
                "$file"
            return "$HANDSSHAKE_CODE_FILE_PERMISSION"
        } ;;
        x) [[ -x "$file" ]] || {
            _log_validation_error \
                "$HANDSSHAKE_MESSAGE_FILE_PERMISSION: Execute \
denied for '$file'" \
                "$file"
            return "$HANDSSHAKE_CODE_FILE_PERMISSION"
        } ;;
    esac

    return 0
}
