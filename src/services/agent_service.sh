# shellcheck shell=bash
set -euo pipefail

# Source dependencies
source "$(dirname "${BASH_SOURCE[0]}")/../util/file_utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/logging_utils.sh"
# ssh_agent_env.sh (now partially integrated or we use its logic here)
# For simplicity and consolidation, implementing logic directly here using ENV file 
# path defined in config.

load_agent_env() {
    if [[ -f "$AGENT_ENV_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$AGENT_ENV_FILE"
    fi
    return 0
}

start_agent() {
    eval "$(ssh-agent -s)" >/dev/null 2>&1
    if [[ -z "${SSH_AUTH_SOCK:-}" ]] || [[ -z "${SSH_AGENT_PID:-}" ]]; then
        log_error "Failed to start ssh-agent."
        exit 1 # Critical failure
    fi
    
    local env_content="export SSH_AUTH_SOCK=${SSH_AUTH_SOCK}
export SSH_AGENT_PID=${SSH_AGENT_PID}"
    
    if ! atomic_write "$AGENT_ENV_FILE" "$env_content"; then
         log_error "Failed to write agent environment file."
         exit 1
    fi
    
    log_info "Started new ssh-agent with PID: $SSH_AGENT_PID."
    echo "Started new ssh-agent with PID: $SSH_AGENT_PID."
    return 0
}

is_agent_valid() {
    if [[ -n "${SSH_AUTH_SOCK:-}" ]] && [[ -n "${SSH_AGENT_PID:-}" ]]; then
        if kill -0 "$SSH_AGENT_PID" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

ensure_agent() {
    # Suppress GUI prompts
    unset SSH_ASKPASS
    unset DISPLAY

    load_agent_env
    if is_agent_valid; then
        export SSH_AUTH_SOCK SSH_AGENT_PID
    else
        start_agent
    fi
    return 0
}

cleanup_agent() {
    echo "Cleaning up..."
    
    if pkill -u "$USER" ssh-agent; then
        log_info "Killed all ssh-agent processes for user $USER."
        echo "Killed ssh-agent processes."
    else
        log_info "No ssh-agent processes found to kill."
        echo "No ssh-agent processes found."
    fi

    # Remove socket files/directories
    find /tmp -maxdepth 1 -user "$USER" -name "ssh-*" -type d -exec rm -rf {} + 2>/dev/null
    find /tmp -maxdepth 1 -user "$USER" -name "ssh-*" -type s -delete 2>/dev/null
    
    log_info "Removed /tmp/ssh-* socket files/directories."
    echo "Removed socket files."

    # Clear state files
    # Note: clear_records is in key_service, but we can clear the file directly here 
    # if we want full cleanup, or we rely on the caller to call clear_records.
    # Ideally agent service should not depend on key service internals.
    if [[ -f "$RECORD_FILE" ]]; then
         rm -f "$RECORD_FILE"
    fi
    
    if [[ -f "$AGENT_ENV_FILE" ]]; then
        rm -f "$AGENT_ENV_FILE"
        log_info "Removed agent environment file."
        echo "Removed agent environment file."
    fi
    return 0
}
