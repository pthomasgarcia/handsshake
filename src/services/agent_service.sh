# shellcheck shell=bash

# Source dependencies
source "$(dirname "${BASH_SOURCE[0]}")/../util/file_utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/logging_utils.sh"
# ssh_agent_env.sh (now partially integrated or we use its logic here)
# For simplicity and consolidation, implementing logic directly here using ENV file 
# path defined in config.

load_agent_env() {
    if [[ -f "$HANDSSHAKE_AGENT_ENV_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$HANDSSHAKE_AGENT_ENV_FILE"
    fi
    return 0
}

start_agent() {
    eval "$(ssh-agent -s)" >/dev/null 2>&1
    if [[ -z "${SSH_AUTH_SOCK:-}" ]] || [[ -z "${SSH_AGENT_PID:-}" ]]; then
        log_error "Failed to start ssh-agent."
        return 1 # Critical failure
    fi
    
    local env_content="export SSH_AUTH_SOCK=${SSH_AUTH_SOCK}
export SSH_AGENT_PID=${SSH_AGENT_PID}"
    
    if ! atomic_write "$HANDSSHAKE_AGENT_ENV_FILE" "$env_content"; then
         log_error "Failed to write agent environment file."
         return 1
    fi
    
    log_info "Started new ssh-agent with PID: $SSH_AGENT_PID."
    echo "Started new ssh-agent with PID: $SSH_AGENT_PID."
    return 0
}

is_agent_valid() {
    if [[ -n "${SSH_AUTH_SOCK:-}" ]] && [[ -n "${SSH_AGENT_PID:-}" ]]; then
        if [[ -S "$SSH_AUTH_SOCK" ]] && kill -0 "$SSH_AGENT_PID" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

ensure_agent() {
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
    
    local stored_sock=""
    local stored_pid=""
    local __parsed_sock=""
    local __parsed_pid=""
    
    if parse_agent_env "$HANDSSHAKE_AGENT_ENV_FILE"; then
        stored_sock="$__parsed_sock"
        stored_pid="$__parsed_pid"

        if kill -0 "$stored_pid" 2>/dev/null; then
             local proc_name
             proc_name=$(ps -p "$stored_pid" -o comm= 2>/dev/null)
             if [[ -n "$proc_name" ]] && [[ "$(basename "$proc_name")" == "ssh-agent" ]]; then
                 kill "$stored_pid"
                 log_info "Killed handsshake ssh-agent (PID: $stored_pid)."
                 echo "Killed ssh-agent (PID: $stored_pid)."
             fi
        fi

        if [[ -S "$stored_sock" ]]; then
            rm -f "$stored_sock"
            log_info "Removed handsshake socket: $stored_sock"
            echo "Removed socket file."
            
            # Also try to remove the parent directory if it's in /tmp and starts with ssh-
            local sock_dir
            sock_dir=$(dirname "$stored_sock")
            if [[ "$sock_dir" == /tmp/ssh-* ]] && [[ -d "$sock_dir" ]]; then
                rmdir "$sock_dir" 2>/dev/null || true
            fi
        fi
    fi

    # Clear state files
    if [[ -f "$HANDSSHAKE_RECORD_FILE" ]]; then
         rm -f "$HANDSSHAKE_RECORD_FILE"
    fi
    
    if [[ -f "$HANDSSHAKE_AGENT_ENV_FILE" ]]; then
        rm -f "$HANDSSHAKE_AGENT_ENV_FILE"
        log_info "Removed agent environment file."
        echo "Removed agent environment file."
    fi
    return 0
}
