# shellcheck shell=bash
set -euo pipefail


load_config() {
    # Loads the SSH agent configuration from a given file and sets default values.
    # Adheres to XDG Base Directory Specification.
    #
    # Args:
    #   $1 (string) - Path to the configuration file (Optional)
    # Returns:
    #   0 if the socket exists and is a socket.
    #   CODE_INVALID_SOCKET if the socket does not exist or is not a socket.

    # XDG Defaults
    local xdg_config_home="${XDG_CONFIG_HOME:-$HOME/.config}/handsshake"
    local xdg_state_home="${XDG_STATE_HOME:-$HOME/.local/state}/handsshake"
    
    # 1. Determine Config File
    local config_file="${1:-$xdg_config_home/settings.conf}"
    
    # Check if config exists, otherwise use defaults without erroring on missing file
    if [[ -f "$config_file" ]]; then
         # validate_file checks perms, which is good practice
         if validate_file "$config_file" "r" 2>/dev/null; then
             # shellcheck source=/dev/null
             source "$config_file"
         fi
    fi

    # 2. Set Defaults (XDG-aware)
    DEFAULT_KEY_TIMEOUT="${DEFAULT_KEY_TIMEOUT:-86400}"
    VERBOSE="${VERBOSE:-true}"
    
    # these are state files, should be in XDG_STATE_HOME
    LOG_FILE="${LOG_FILE:-$xdg_state_home/logs/handsshake.log}"
    AGENT_ENV_FILE="${AGENT_ENV_FILE:-$xdg_state_home/ssh-agent.env}"
    RECORD_FILE="${RECORD_FILE:-$xdg_state_home/added_keys.list}"
    LOCK_FILE="${LOCK_FILE:-$xdg_state_home/handsshake.lock}"

    # Validate DEFAULT_KEY_TIMEOUT
    if ! [[ "$DEFAULT_KEY_TIMEOUT" =~ ^[0-9]+$ ]]; then
        echo "Error: DEFAULT_KEY_TIMEOUT is not a valid number. Using default (86400)." >&2
        DEFAULT_KEY_TIMEOUT=86400
    fi

    # 3. Ensure Directories Exist
    ensure_directory "$(dirname "$LOG_FILE")" || return $?
    ensure_directory "$(dirname "$AGENT_ENV_FILE")" || return $?
    
    # Secure the log file
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE"
    fi
    secure_file "$LOG_FILE"

    return 0
}
