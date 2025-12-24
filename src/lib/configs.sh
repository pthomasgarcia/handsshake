# shellcheck shell=bash

if [[ -n "${HANDSSHAKE_CONFIGS_LOADED:-}" ]]; then
    return 0
fi
HANDSSHAKE_CONFIGS_LOADED=true

# Source dependencies
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../util/validators.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../util/files.sh"

configs::init() {
    # Loads the SSH agent configuration from a given file and sets
    # default values. Adheres to XDG Base Directory Specification.
    #
    # Args:
    #   $1 (string) - Path to the configuration file (Optional)
    # Returns:
    #   0 if the socket exists and is a socket.
    #   Non-zero if directory creation fails.

    # XDG Defaults
    local xdg_config_home="${XDG_CONFIG_HOME:-$HOME/.config}/handsshake"
    local xdg_state_home="${XDG_STATE_HOME:-$HOME/.local/state}/handsshake"

    # 2. Set Defaults (XDG-aware)
    HANDSSHAKE_DEFAULT_TIMEOUT="${HANDSSHAKE_DEFAULT_TIMEOUT:-86400}"
    HANDSSHAKE_VERBOSE="${HANDSSHAKE_VERBOSE:-true}"
    HANDSSHAKE_DEFAULT_KEY="${HANDSSHAKE_DEFAULT_KEY:-$HOME/.ssh/id_ed25519}"

    # these are state files, should be in XDG_STATE_HOME
    : "${HANDSSHAKE_LOG_FILE:=$xdg_state_home/logs/handsshake.log}"
    : "${HANDSSHAKE_AGENT_ENV_FILE:=$xdg_state_home/ssh-agent.env}"
    : "${HANDSSHAKE_RECORD_FILE:=$xdg_state_home/added_keys.list}"
    : "${HANDSSHAKE_LOCK_FILE:=$xdg_state_home/handsshake.lock}"

    # 1. Determine Config File
    local config_file="${1:-$xdg_config_home/settings.conf}"

    # Use defaults without erroring on missing file if config doesn't exist
    if [[ -f "$config_file" ]]; then
        # validate_file checks perms, which is good practice
        if validators::file "$config_file" "r" 2> /dev/null; then
            # shellcheck source=/dev/null
            source "$config_file"
        fi
    fi

    # Validate HANDSSHAKE_DEFAULT_TIMEOUT
    if ! [[ "$HANDSSHAKE_DEFAULT_TIMEOUT" =~ ^[0-9]+$ ]]; then
        echo "Error: HANDSSHAKE_DEFAULT_TIMEOUT is not a valid number. \
Using default (86400)." >&2
        HANDSSHAKE_DEFAULT_TIMEOUT=86400
    fi

    # 3. Ensure Directories Exist
    validators::ensure_directory "$(dirname "$HANDSSHAKE_LOG_FILE")" ||
        return $?
    validators::ensure_directory "$(dirname "$HANDSSHAKE_AGENT_ENV_FILE")" ||
        return $?
    validators::ensure_directory "$(dirname "$HANDSSHAKE_RECORD_FILE")" ||
        return $?
    validators::ensure_directory "$(dirname "$HANDSSHAKE_LOCK_FILE")" ||
        return $?
    if [[ ! -f "$HANDSSHAKE_LOG_FILE" ]]; then
        touch "$HANDSSHAKE_LOG_FILE"
    fi
    files::secure "$HANDSSHAKE_LOG_FILE"

    # Secure other state files
    if [[ ! -f "$HANDSSHAKE_AGENT_ENV_FILE" ]]; then
        touch "$HANDSSHAKE_AGENT_ENV_FILE"
    fi
    files::secure "$HANDSSHAKE_AGENT_ENV_FILE"

    if [[ ! -f "$HANDSSHAKE_RECORD_FILE" ]]; then
        touch "$HANDSSHAKE_RECORD_FILE"
    fi
    files::secure "$HANDSSHAKE_RECORD_FILE"

    if [[ ! -f "$HANDSSHAKE_LOCK_FILE" ]]; then
        touch "$HANDSSHAKE_LOCK_FILE"
    fi
    files::secure "$HANDSSHAKE_LOCK_FILE"

    return 0
}
