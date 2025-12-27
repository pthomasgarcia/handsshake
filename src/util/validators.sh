#!/usr/bin/env bash
# shellcheck shell=bash
# ---------------------------------------------------------------------------
#  HandSSHAKE – validator library
#  ORDER: guards → internal → scalar → numeric → constraints → fs → ssh
# ---------------------------------------------------------------------------

# ---------- 1. Idempotency guard (SSH spelling kept) ----------
[[ -n "${HANDSSHAKE_VALIDATORS_LOADED:-}" ]] && return 0
HANDSSHAKE_VALIDATORS_LOADED=true

# ---------- 2. Strict mode (opt-in) ----------
if [[ ${HANDSHAKE_STRICT_MODE:-false} == true ]]; then
    set -euo pipefail
    shopt -s inherit_errexit
fi

# ---------- 3. Imports ----------
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/loggers.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/constants.sh"

###############################################################################
# INTERNAL HELPERS – not for public use
###############################################################################

# Safe trim: returns trimmed string on STDOUT, always 0
validators::_trim() {
    local var=$*                       # concat args to single string
    var=${var#"${var%%[![:space:]]*}"} # leading
    var=${var%"${var##*[![:space:]]}"} # trailing
    printf '%s\n' "$var"               # %s\n avoids leading-dash problem
}

# Centralised error logger – respects HANDSSHAKE_VERBOSE
validators::_log_err() {
    local msg=$1 input=$2
    if [[ ${HANDSSHAKE_VERBOSE:-false} == true ]]; then
        loggers::error "$msg: Input '$input'"
    fi
}

# Shared pattern validator – *prints* trimmed value on success
validators::_check_regex() {
    local raw=$1 pattern=$2 errCode=$3 errMsg=$4
    local trimmed
    trimmed=$(validators::_trim "$raw") || return $? # propagate trim failure

    # turn off globbing for the test
    (
        shopt -u failglob nullglob dotglob
        [[ $trimmed =~ ^($pattern)$ ]] || {
            validators::_log_err "$errMsg" "$raw"
            return "$errCode"
        }
    ) || return $?

    printf '%s\n' "$trimmed"
}

###############################################################################
# SCALAR VALIDATORS
###############################################################################

# Non-empty string (after trim)
validators::string() {
    local trimmed
    trimmed=$(validators::_trim "$1") || return $?
    [[ -n $trimmed ]] || {
        validators::_log_err "$HANDSSHAKE_MESSAGE_EMPTY_STRING" "$1"
        return "$HANDSSHAKE_CODE_EMPTY_STRING"
    }
    printf '%s\n' "$trimmed"
}

# Whitelist sanitiser – ASCII only, keeps space ,.;:_-
validators::sanitize_string() {
    local input=$1
    printf '%s\n' "${input//[!a-zA-Z0-9 ,.;:_-]/}"
}

# Boolean – true/false/yes/no/1/0  (case insensitive)
validators::boolean() {
    local input=${1,,} # lowercase
    validators::_check_regex "$input" "$HANDSSHAKE_PATTERN_BOOL" \
        "$HANDSSHAKE_CODE_INVALID_BOOLEAN" \
        "$HANDSSHAKE_MESSAGE_INVALID_BOOLEAN"
}

###############################################################################
# NUMERIC VALIDATORS
###############################################################################

# Signed integer
validators::signed_integer() {
    validators::_check_regex "$1" "$HANDSSHAKE_PATTERN_INT" \
        "$HANDSSHAKE_CODE_INVALID_INTEGER" \
        "$HANDSSHAKE_MESSAGE_INVALID_INTEGER"
}

# Signed float
validators::signed_float() {
    validators::_check_regex "$1" "$HANDSSHAKE_PATTERN_FLOAT" \
        "$HANDSSHAKE_CODE_INVALID_FLOAT" \
        "$HANDSSHAKE_MESSAGE_INVALID_FLOAT"
}

# Wrapper: reuse signed_integer for timeout 1-86400
validators::timeout() {
    local secs
    secs=$(validators::signed_integer "$1") || return $?
    ((secs > 0 && secs <= 86400)) || {
        validators::_log_err "Timeout must be 1-86400 s" "$1"
        return "$HANDSSHAKE_CODE_OUT_OF_RANGE"
    }
    printf '%s\n' "$secs"
}

###############################################################################
# NUMERIC CONSTRAINTS (compose the above)
###############################################################################

# Negative sign gate
validators::negative_allowed() {
    local integer is_negative_allowed
    integer=$(validators::signed_integer "$1") || return $?
    is_negative_allowed=$(validators::boolean "${2:-true}") || return $?

    if [[ $is_negative_allowed == false && $integer -lt 0 ]]; then
        validators::_log_err "$HANDSSHAKE_MESSAGE_NEGATIVE_NOT_ALLOWED" "$1"
        return "$HANDSSHAKE_CODE_NEGATIVE_NOT_ALLOWED"
    fi
    printf '%s\n' "$integer"
}

# 64-bit range check
validators::int64() {
    local integer=$1
    local check64
    check64=$(validators::boolean "${2:-false}") || return $?

    if [[ $check64 == true ]]; then
        ((integer >= HANDSSHAKE_INT64_MIN && \
        integer <= HANDSSHAKE_INT64_MAX)) || {
            validators::_log_err "$HANDSSHAKE_MESSAGE_EXCEEDS_64BIT" "$integer"
            return "$HANDSSHAKE_CODE_EXCEEDS_64BIT"
        }
    fi
    printf '%s\n' "$integer"
}

# Range gate  (inclusive min/max)
validators::range() {
    local integer=$1 min=${2:-} max=${3:-}
    integer=$(validators::signed_integer "$integer") || return $?

    [[ -n $min ]] && min=$(validators::signed_integer "$min") || return $?
    [[ -n $max ]] && max=$(validators::signed_integer "$max") || return $?

    if [[ -n $min && $integer -lt $min ]]; then
        validators::_log_err "Value '$integer' < min '$min'" "$integer"
        return "$HANDSSHAKE_CODE_OUT_OF_RANGE"
    fi
    if [[ -n $max && $integer -gt $max ]]; then
        validators::_log_err "Value '$integer' > max '$max'" "$integer"
        return "$HANDSSHAKE_CODE_OUT_OF_RANGE"
    fi
    printf '%s\n' "$integer"
}

# All-in-one integer validator
validators::int_constraints() {
    local integer=$1
    integer=$(validators::signed_integer "$integer") || return $?
    integer=$(validators::negative_allowed "$integer" "${4:-true}") || return $?
    integer=$(validators::int64 "$integer" "${5:-false}") || return $?
    integer=$(validators::range "$integer" "${2:-}" "${3:-}") || return $?
    printf '%s\n' "$integer"
}

###############################################################################
# FILE-SYSTEM VALIDATORS
###############################################################################

# File existence (generic)
validators::file_exists() {
    local file=$1
    local msg=${2:-"File not found: '$file'"}
    [[ -n $file ]] || {
        loggers::error "No file path provided"
        return 1
    }
    [[ -f $file ]] || {
        loggers::error "$msg"
        return 1
    }
}

# Directory existence + optional writability
validators::directory() {
    local dir raw_writable
    dir=$(validators::_trim "$1") || return $?
    raw_writable=$(validators::boolean "${2:-false}") || return $?

    local resolved
    resolved=$(realpath -e "$dir" 2> /dev/null) || resolved=$dir
    [[ -d $resolved ]] || {
        validators::_log_err "$HANDSSHAKE_MESSAGE_DIRECTORY_NOT_FOUND" "$dir"
        return "$HANDSSHAKE_CODE_DIRECTORY_NOT_FOUND"
    }
    if [[ $raw_writable == true && ! -w $resolved ]]; then
        validators::_log_err "$HANDSSHAKE_MESSAGE_DIRECTORY_NOT_WRITABLE" "$dir"
        return "$HANDSSHAKE_CODE_DIRECTORY_NOT_WRITABLE"
    fi
}

# mkdir -p + ensure writable
validators::ensure_directory() {
    local dir=$1
    [[ -d $dir ]] || mkdir -p -- "$dir" || {
        validators::_log_err "Failed to create directory" "$dir"
        return "$HANDSSHAKE_CODE_FILE_PERMISSION"
    }
    validators::directory "$dir" true
}

# File with permission gate  (r/w/x)
validators::file() {
    local file perm
    file=$(validators::_trim "$1") || return $?
    perm=${2:-r}

    [[ -e $file ]] || {
        validators::_log_err "$HANDSSHAKE_MESSAGE_FILE_NOT_FOUND" "$file"
        return "$HANDSSHAKE_CODE_FILE_NOT_FOUND"
    }
    case $perm in
        r) [[ -r $file ]] || return "$HANDSSHAKE_CODE_FILE_PERMISSION" ;;
        w) [[ -w $file ]] || return "$HANDSSHAKE_CODE_FILE_PERMISSION" ;;
        x) [[ -x $file ]] || return "$HANDSSHAKE_CODE_FILE_PERMISSION" ;;
        *)
            validators::_log_err "Invalid permission mode '$perm'" "$perm"
            return "$HANDSSHAKE_CODE_FILE_PERMISSION"
            ;;
    esac
}

# Unix-domain socket
validators::socket() {
    local path
    path=$(validators::_trim "$1") || return $?
    [[ -S $path ]] || {
        validators::_log_err "$HANDSSHAKE_MESSAGE_SOCKET_NOT_FOUND" "$path"
        return "$HANDSSHAKE_CODE_SOCKET_NOT_FOUND"
    }
}

###############################################################################
# SSH / EXECUTION-CONTEXT HELPERS
###############################################################################

# Am I being sourced?
validators::is_sourced() {
    local result
    [[ ${BASH_SOURCE[0]} != "$0" ]] && result=0 || result=1
    [[ ${DEBUG:-} == 1 ]] &&
        echo "Debug[validators::is_sourced]: context=$result" >&2
    return "$result"
}

# Fail with helpful message if sourcing required
validators::require_sourcing() {
    local cmd=${1:-}
    if ! validators::is_sourced; then
        local user_rc=".${SHELL##*/}rc"
        # Using the last element in BASH_SOURCE to find the entry script
        local script=${BASH_SOURCE[-1]}

        # Call the logger utility
        loggers::format error "Command '$cmd' requires shell integration"
        loggers::format warning "This command requires shell integration."
        loggers::format warning "Variables will not persist in subshells."

        echo >&2 # Just a spacer

        loggers::format info "Fix: source $script $cmd"
        loggers::format info "Or add to ~/$user_rc:"
        echo -e "  ${FMT_CYAN}alias handsshake='source $script'${FMT_RESET}" >&2

        return 1
    fi
}

# Basic tool-chain check
validators::environment() {
    local missing=()
    for tool in ssh ssh-add ssh-agent; do
        command -v "$tool" &> /dev/null || missing+=("$tool")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        loggers::error "Missing required tools: ${missing[*]}"
        return 1
    fi
}

# SSH key sanity
validators::ssh_key() {
    local key=${1:-}
    [[ -n $key && -r $key ]]
}

# Command whitelist for direct execution
validators::command_context() {
    local cmd=$1
    local -a direct=(health list keys version cleanup help
        -h --help -v --version -l --list
        -k --keys -c --cleanup -H --health)
    local c
    for c in "${direct[@]}"; do [[ $cmd == "$c" ]] && return 0; done
    return 1
}

# Debug dump
validators::debug_status() {
    [[ ${DEBUG:-} == 1 ]] || return 0
    echo "Debug[validators]: Debug mode enabled" >&2
    if validators::is_sourced; then
        echo "Debug[validators]: Context = sourced" >&2
    else
        echo "Debug[validators]: Context = executed directly" >&2
    fi
    if validators::environment; then
        echo "Debug[validators]: Environment = pass" >&2
    else
        echo "Debug[validators]: Environment = fail" >&2
    fi
}

# ---------------------------------------------------------------------------
# End of reorganised validator library
# ---------------------------------------------------------------------------
