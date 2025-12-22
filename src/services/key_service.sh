# shellcheck shell=bash

# --- Dependencies ---
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../util/file_utils.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../util/logging_utils.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../util/validation_utils.sh"

# --- Record Management (Internal) ---

record_key() {
    local key_file
    key_file=$(realpath "$1" 2>/dev/null || echo "$1")
    if [[ -f "$HANDSSHAKE_RECORD_FILE" ]] &&
        grep -Fxq "$key_file" "$HANDSSHAKE_RECORD_FILE"; then
        return 0
    fi
    echo "$key_file" >>"$HANDSSHAKE_RECORD_FILE"
}

detach_record() {
    local key_file="$1"
    if [[ -f "$HANDSSHAKE_RECORD_FILE" ]]; then
        local tmp_content
        tmp_content=$(grep -Fxv "$key_file" "$HANDSSHAKE_RECORD_FILE" || true)
        atomic_write "$HANDSSHAKE_RECORD_FILE" "$tmp_content"
    fi
}

clear_records() {
    if [[ -f "$HANDSSHAKE_RECORD_FILE" ]]; then
        rm -f "$HANDSSHAKE_RECORD_FILE"
    fi
}

# --- Primary Service Commands ---

# Usage: attach [key_file]
attach() {
    ensure_agent
    local key_file="${1:-$HOME/.ssh/id_ed25519}"

    if [[ "$key_file" == "$HOME/.ssh/id_ed25519" ]] && [[ -z "${1:-}" ]]; then
        echo "No key specified. Using default: $key_file"
    fi

    if ! validate_file "$key_file" "r" 2>/dev/null; then
        echo "Invalid key file: '$key_file' is missing or not readable." >&2
        return 1
    fi

    echo "Attaching key '$key_file'..."
    if ssh-add -t "$HANDSSHAKE_DEFAULT_TIMEOUT" "$key_file"; then
        log_info "Key '$key_file' attached \
(timeout: ${HANDSSHAKE_DEFAULT_TIMEOUT}s)."
        echo "Key '$key_file' attached."
        record_key "$key_file"
    else
        log_error "Failed to attach key '$key_file'."
        return 1
    fi
}

# Usage: detach <key_file>
detach() {
    ensure_agent
    local key_file="${1:-}"

    if [[ -z "$key_file" ]]; then
        echo "Error: detach requires exactly one fingerprint/key_file." >&2
        return 1
    fi

    # We attempt to detach from the agent even if the file is missing locally
    echo "Detaching key '$key_file'..."
    if ssh-add -d "$key_file" 2>/dev/null; then
        log_info "Detached key '$key_file' from agent."
        echo "Key '$key_file' detached."
    else
        log_warn "Key '$key_file' was not in the agent or file missing."
        echo "Warning: Key '$key_file' not found in agent." >&2
        detach_record "$key_file"
        return 1
    fi

    # Always clean the record to maintain consistency
    detach_record "$key_file"
}

# Usage: flush
flush() {
    ensure_agent
    echo "Flushing all keys from agent..."
    if ssh-add -D; then
        log_info "Flushed all keys from ssh-agent."
        echo "All keys flushed."
        clear_records
    else
        log_error "Failed to flush keys."
        return 1
    fi
}

# Usage: list
list_keys() {
    ensure_agent
    local out
    out=$(ssh-add -l 2>&1)
    local code=$?

    if [[ $code -eq 0 ]]; then
        echo "Attached keys:"
        # In tests, we want to see the comment which might contain the path
        echo "$out"
    elif [[ $code -eq 1 ]]; then
        echo "Agent is empty (no keys attached)."
    else
        echo "Error: Could not connect to agent." >&2
        return 1
    fi
}

# Usage: keys
# Maps to keys|-k|--keys) keys "$@" ;;
keys() {
    ensure_agent
    ssh-add -L
}

# Usage: timeout <seconds>
timeout() {
    ensure_agent
    local new_timeout="${1:-}"

    if [[ -z "$new_timeout" ]]; then
        echo "Error: timeout requires exactly one argument." >&2
        return 1
    fi

    if ! [[ "$new_timeout" =~ ^[0-9]+$ ]] ||
        [[ "$new_timeout" -gt 86400 ]]; then
        echo "Error: positive integer required (max 86400)." >&2
        return 1
    fi

    if [[ ! -f "$HANDSSHAKE_RECORD_FILE" ]] ||
        [[ ! -s "$HANDSSHAKE_RECORD_FILE" ]]; then
        echo "No keys currently recorded to update." >&2
        return 0
    fi

    echo "Updating timeout for all recorded keys to ${new_timeout}s..."
    local updated=0
    # Use a temporary file to avoid issues with reading and modifying records
    local record_copy
    record_copy=$(mktemp)
    cp "$HANDSSHAKE_RECORD_FILE" "$record_copy"

    while IFS= read -r key_file || [[ -n "$key_file" ]]; do
        [[ -z "$key_file" ]] && continue
        # Ensure we have the absolute path for ssh-add -d
        local abs_key
        abs_key=$(realpath "$key_file" 2>/dev/null || echo "$key_file")
        if [[ -f "$abs_key" ]]; then
            # Re-attach with new timeout
            # Use || true to avoid triggering set -e if ssh-add fails
            ssh-add -d "$abs_key" >/dev/null 2>&1 || true
            if ssh-add -t "$new_timeout" "$abs_key" >/dev/null 2>&1; then
                updated=$((updated + 1))
            fi
        fi
    done <"$record_copy"
    rm -f "$record_copy"

    echo "Updated $updated keys."
    log_info "Global timeout updated to ${new_timeout}s for $updated keys."
    return 0
}
