# shellcheck shell=bash

# --- Dependencies ---
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../util/files.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../util/loggers.sh"

# --- Internal Agent Lifecycle ---

agents::_load_env() {
    local __parsed_sock=""
    local __parsed_pid=""
    if files::parse_agent_env "$HANDSSHAKE_AGENT_ENV_FILE"; then
        export SSH_AUTH_SOCK="$__parsed_sock"
        export SSH_AGENT_PID="$__parsed_pid"
    fi
    return 0
}

agents::start() {
    local agent_out
    agent_out=$(ssh-agent -s)
    SSH_AUTH_SOCK=$(echo "$agent_out" |
        sed -n 's/SSH_AUTH_SOCK=\([^;]*\);.*/\1/p')
    SSH_AGENT_PID=$(echo "$agent_out" |
        sed -n 's/SSH_AGENT_PID=\([^;]*\);.*/\1/p')

    if [[ -z "${SSH_AUTH_SOCK:-}" ]] || [[ -z "${SSH_AGENT_PID:-}" ]]; then
        loggers::error "Failed to start ssh-agent."
        return 1
    fi

    export SSH_AUTH_SOCK
    export SSH_AGENT_PID

    local env_content="SSH_AUTH_SOCK=${SSH_AUTH_SOCK}
SSH_AGENT_PID=${SSH_AGENT_PID}"

    if ! files::atomic_write "$HANDSSHAKE_AGENT_ENV_FILE" "$env_content"; then
        loggers::error "Failed to write agent environment file."
        return 1
    fi

    loggers::info "Started new ssh-agent with PID: $SSH_AGENT_PID."
    echo "Started new ssh-agent with PID: $SSH_AGENT_PID."
    return 0
}

agents::_is_valid() {
    if [[ -n "${SSH_AUTH_SOCK:-}" ]] && [[ -n "${SSH_AGENT_PID:-}" ]]; then
        if [[ -S "$SSH_AUTH_SOCK" ]] &&
            kill -0 "$SSH_AGENT_PID" 2> /dev/null; then
            return 0
        fi
    fi
    return 1
}

agents::ensure() {
    agents::_load_env
    if ! agents::_is_valid; then
        agents::start
    fi
    return 0
}

# --- Service Commands (Called by Dispatcher) ---

# Usage: cleanup
# Renamed from cleanup_agent to match dispatcher
agents::stop() {
    echo "Cleaning up..."

    local stored_sock=""
    local stored_pid=""
    local __parsed_sock=""
    local __parsed_pid=""

    if files::parse_agent_env "$HANDSSHAKE_AGENT_ENV_FILE"; then
        stored_sock="$__parsed_sock"
        stored_pid="$__parsed_pid"

        if kill -0 "$stored_pid" 2> /dev/null; then
            local proc_name
            proc_name=$(ps -p "$stored_pid" -o comm= 2> /dev/null)
            if [[ -n "$proc_name" ]] &&
                [[ "$(basename "$proc_name")" == "ssh-agent" ]]; then
                kill "$stored_pid"
                loggers::info "Killed handsshake ssh-agent (PID: $stored_pid)."
                echo "Killed ssh-agent (PID: $stored_pid)."
            fi
        fi

        if [[ -S "$stored_sock" ]]; then
            rm -f "$stored_sock"
            loggers::info "Removed handsshake socket: $stored_sock"
            echo "Removed socket file."

            local sock_dir
            sock_dir=$(dirname "$stored_sock")
            if [[ "$sock_dir" == /tmp/ssh-* ]] && [[ -d "$sock_dir" ]]; then
                rmdir "$sock_dir" 2> /dev/null || true
            fi
        fi
    fi

    # Clear state files
    if [[ -f "$HANDSSHAKE_RECORD_FILE" ]]; then
        rm -f "$HANDSSHAKE_RECORD_FILE"
    fi

    if [[ -f "$HANDSSHAKE_AGENT_ENV_FILE" ]]; then
        rm -f "$HANDSSHAKE_AGENT_ENV_FILE"
        loggers::info "Removed agent environment file."
        echo "Removed agent environment file."
    fi
    return 0
}

# Usage: version
# Maps to version|-v|--version) version "$@" ;;
agents::version() {
    echo "handsshake v${HANDSSHAKE_VERSION}"
}
