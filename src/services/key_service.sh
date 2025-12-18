# shellcheck shell=bash
set -euo pipefail

# Source dependencies
source "$(dirname "${BASH_SOURCE[0]}")/../util/file_utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/logging_utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/validation_utils.sh"

record_key() {
    local key_file="$1"
    if [[ -f "$RECORD_FILE" ]] && grep -Fxq "$key_file" "$RECORD_FILE"; then
        return 0
    fi
    # Direct append, relying on higher-level lock
    echo "$key_file" >> "$RECORD_FILE"
    return 0
}

remove_key_record() {
    local key_file="$1"
    if [[ -f "$RECORD_FILE" ]]; then
        local tmp_content
        tmp_content=$(grep -Fxv "$key_file" "$RECORD_FILE" || true)
        atomic_write "$RECORD_FILE" "$tmp_content"
    fi
    return 0
}

clear_records() {
    if [[ -f "$RECORD_FILE" ]]; then
        rm -f "$RECORD_FILE"
    fi
    return 0
}

add_key() {
    local key_file="${1:-$HOME/.ssh/id_rsa}"

    if [[ "$key_file" == "$HOME/.ssh/id_rsa" ]] && [[ -z "${1:-}" ]]; then
        echo "No key specified. Using default: $key_file"
    fi

    if ! validate_file "$key_file" "r" 2>/dev/null; then
         echo "Key file '$key_file' is missing or not readable." >&2
         return 1
    fi

    echo "Adding key '$key_file'..."
    if ssh-add -t "$DEFAULT_KEY_TIMEOUT" "$key_file"; then
        log_info "Added key '$key_file' with timeout ${DEFAULT_KEY_TIMEOUT}s."
        echo "Key '$key_file' added with timeout ${DEFAULT_KEY_TIMEOUT}s."
        record_key "$key_file"
        return 0
    else
        log_error "Failed to add key '$key_file'."
        echo "Failed to add key '$key_file'." >&2
        return 1
    fi
}

remove_key() {
    local key_file="$1"
    if ! validate_file "$key_file" "r" 2>/dev/null; then
        echo "Key file '$key_file' is missing or not readable." >&2
        return 1
    fi

    echo "Removing key '$key_file'..."
    if ssh-add -d "$key_file"; then
        log_info "Removed key '$key_file'."
        echo "Key '$key_file' removed."
        remove_key_record "$key_file"
        return 0
    else
        # ssh-add returns non-zero if key wasn't in agent, but we should still clean record
        local status=$?
        log_error "Failed to remove key '$key_file' from agent (Status: $status). Cleaning record anyway."
        echo "Warning: Key '$key_file' might not have been in the agent." >&2
        # Clean record regardless
        remove_key_record "$key_file"
        # We don't return 1 here because we successfully ensured it's gone from records
        return 0
    fi
}

remove_all_keys() {
    echo "Removing all keys..."
    if ssh-add -D; then
        log_info "Removed all keys from ssh-agent."
        echo "All keys removed."
        clear_records
        return 0
    else
        log_error "Failed to remove all keys."
        echo "Failed to remove keys." >&2
        return 1
    fi
}

list_keys() {
    echo "Current SSH agent keys:"
    if ssh-add -l 2>/dev/null; then
        return 0
    else
        # We assume listing is called when agent should be running.
        # However, if ssh-add fails, it might be no keys or no agent.
        # Checking exit code 1 (no keys) vs 2 (no agent) is standard but varies.
        # For simplicity, we print "No keys loaded" if valid agent but empty.
        echo "No keys loaded."
        return 0
    fi
}

update_key_timeout() {
    local new_timeout="$1"

    if ! [[ "$new_timeout" =~ ^[0-9]+$ ]] || [[ "$new_timeout" -gt 86400 ]]; then
        echo "Timeout must be a positive integer <= 86400." >&2
        return 1
    fi

    if [[ ! -f "$RECORD_FILE" ]]; then
        echo "No keys recorded to update." >&2
        return 1
    fi

    local updated=0
    local key_file
    while IFS= read -r key_file || [ -n "$key_file" ]; do
        if validate_file "$key_file" "r" 2>/dev/null; then
            echo "Updating timeout for key '$key_file'..."
            ssh-add -d "$key_file" >/dev/null 2>&1 || true
            if ssh-add -t "$new_timeout" "$key_file"; then
                log_info "Updated timeout for key '$key_file' to ${new_timeout}s."
                echo "Timeout updated for '$key_file'."
                updated=$((updated + 1))
            else
                log_error "Failed to update timeout for key '$key_file'."
                echo "Failed to update timeout for '$key_file'." >&2
            fi
        fi
    done < "$RECORD_FILE"

    if [[ "$updated" -eq 0 ]]; then
        return 1
    fi
    return 0
}
