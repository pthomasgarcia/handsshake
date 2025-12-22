# shellcheck shell=bash
# Source dependencies
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../util/file_utils.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../util/logging_utils.sh"

health() {
    echo "Health Check:"
    local ssh_dir="$HOME/.ssh"
    local default_key="$ssh_dir/id_ed25519"
    local status="OK"

    # Agent Status
    echo "  [Agent Status]"
    echo "  Current shell SSH_AUTH_SOCK: ${SSH_AUTH_SOCK:-<unset>}"
    echo "  Current shell SSH_AGENT_PID: ${SSH_AGENT_PID:-<unset>}"

    local stored_sock=""
    local stored_pid=""
    local __parsed_sock=""
    local __parsed_pid=""
    if parse_agent_env "$HANDSSHAKE_AGENT_ENV_FILE"; then
        stored_sock="$__parsed_sock"
        stored_pid="$__parsed_pid"
        echo "  Stored handsshake socket: ${stored_sock:-<none>}"
        echo "  Stored handsshake PID:    ${stored_pid:-<none>}"
    fi

    if [[ -n "$stored_sock" ]] && [[ "$SSH_AUTH_SOCK" != "$stored_sock" ]]; then
        echo "  [WARNING] Environment mismatch! Your shell is not using the \
handsshake agent."
        echo "            Make sure you 'source' the script: \
alias handsshake='source ...'"
        status="WARNING"
    fi

    if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
        if [[ -S "$SSH_AUTH_SOCK" ]]; then
            echo "  [OK] Socket file exists."
        else
            echo "  [ERROR] Socket file missing or not a socket."
            status="ERROR"
        fi

        # ssh-add -l exit codes:
        # 0: keys found
        # 1: no identities
        # 2: could not contact agent
        local ssh_add_out
        ssh_add_out=$(ssh-add -l 2>&1) || local ssh_add_exit=$?
        ssh_add_exit=${ssh_add_exit:-0}

        if [[ "$ssh_add_exit" -eq 0 ]]; then
            echo "  [OK] Agent is reachable."
            local key_count
            key_count=$(echo "$ssh_add_out" | wc -l)
            echo "  Keys loaded: $key_count"
        elif [[ "$ssh_add_exit" -eq 1 ]]; then
            echo "  [OK] Agent is reachable (but empty)."
            echo "  Keys loaded: 0"
        else
            echo "  [ERROR] Agent unreachable: $ssh_add_out"
            status="ERROR"
        fi
    else
        echo "  [ERROR] SSH_AUTH_SOCK not set."
        status="ERROR"
    fi

    # Check .ssh directory
    echo "  [File System]"
    if [[ -d "$ssh_dir" ]]; then
        echo "  [OK] $ssh_dir exists."
    else
        echo "  [WARNING] $ssh_dir does not exist."
        status="WARNING"
    fi

    local perms
    # Check permissions
    if [[ -d "$ssh_dir" ]]; then
        if [[ "${OSTYPE:-}" == "darwin"* ]]; then
            perms=$(stat -f "%Lp" "$ssh_dir" 2>/dev/null || echo "000")
        else
            perms=$(stat -c "%a" "$ssh_dir" 2>/dev/null || echo "000")
        fi

        if [[ "$perms" == "700" ]]; then
            echo "  [OK] $ssh_dir permissions are 700."
        else
            echo "  [WARNING] $ssh_dir permissions are $perms (expected 700)."
            if [[ "$status" == "OK" ]]; then status="WARNING"; fi
        fi
    fi

    # Check default key
    if [[ -f "$default_key" ]]; then
        echo "  [OK] Default key $default_key exists."
    else
        echo "  [INFO] Default key $default_key not found (not critical)."
    fi

    echo "Overall Status: $status"
    if [[ "$status" == "ERROR" ]]; then
        return 1
    fi
    return 0
}
