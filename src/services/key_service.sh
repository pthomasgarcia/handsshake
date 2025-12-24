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
    # Normalize path to prevent duplicates from symlinks/relative paths
    key_file=$(readlink -f "$1" 2> /dev/null ||
        realpath "$1" 2> /dev/null ||
        echo "$1")

    if [[ -z "$key_file" ]]; then
        return 1
    fi

    if [[ -f "$HANDSSHAKE_RECORD_FILE" ]] &&
        grep -Fxq "$key_file" "$HANDSSHAKE_RECORD_FILE"; then
        return 0
    fi
    echo "$key_file" >> "$HANDSSHAKE_RECORD_FILE"
}

detach_record() {
    local key_file="$1"
    if [[ -f "$HANDSSHAKE_RECORD_FILE" ]]; then
        local tmp_content
        tmp_content=$(grep -Fxv "$key_file" "$HANDSSHAKE_RECORD_FILE" || true)
        if [[ -z "$tmp_content" ]]; then
            rm -f "$HANDSSHAKE_RECORD_FILE"
        else
            atomic_write "$HANDSSHAKE_RECORD_FILE" "$tmp_content"
        fi
    fi
}

clear_records() {
    if [[ -f "$HANDSSHAKE_RECORD_FILE" ]]; then
        rm -f "$HANDSSHAKE_RECORD_FILE"
    fi
}

# --- Key Information ---

get_key_fingerprint() {
    local key_file="$1"
    local fingerprint
    # Extract SHA256 fingerprint
    fingerprint=$(ssh-keygen -lf "$key_file" 2> /dev/null | awk '{print $2}')
    if [[ -n "$fingerprint" ]]; then
        echo "$fingerprint"
        return 0
    fi
    return 1
}

# --- Primary Service Commands ---

# Usage: attach [key_file]
attach() {
    ensure_agent
    local key_file="${1:-$HANDSSHAKE_DEFAULT_KEY}"

    if [[ "$key_file" == "$HANDSSHAKE_DEFAULT_KEY" ]] && [[ -z "${1:-}" ]]; then
        echo "No key specified. Using default: $key_file"
    fi

    if ! validate_file "$key_file" "r" 2> /dev/null; then
        echo "Invalid key file: '$key_file' is missing or not readable." >&2
        return 1
    fi

    # Verify it's a valid SSH key and get fingerprint
    local fingerprint
    if ! fingerprint=$(get_key_fingerprint "$key_file"); then
        echo "Invalid key file: '$key_file' is not a valid SSH key." >&2
        return 1
    fi

    # Check if key is already in agent (avoid duplicate attach)
    if ssh-add -l 2> /dev/null | grep -q "$fingerprint"; then
        log_info "Key '$key_file' already in agent (fingerprint: $fingerprint)."
        echo "Key '$key_file' already attached."
        record_key "$key_file"
        return 0
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

    if [[ -z "$key_file" ]] || [[ "$#" -ne 1 ]]; then
        echo "Error: detach requires exactly one fingerprint/key_file." >&2
        return 1
    fi

    # We attempt to detach from the agent even if the file is missing locally
    echo "Detaching key '$key_file'..."
    if ssh-add -d "$key_file" 2> /dev/null; then
        log_info "Detached key '$key_file' from agent."
        echo "Key '$key_file' detached."
    else
        # If it failed, it might be because the file is missing,
        # but we should still check if it was in our record
        if [[ -f "$HANDSSHAKE_RECORD_FILE" ]] &&
            grep -Fxq "$key_file" "$HANDSSHAKE_RECORD_FILE"; then
            log_warn "Key '$key_file' file missing but was in record. \
Cleaning up record."
            echo "Key '$key_file' detached."
            detach_record "$key_file"
            return 0 # Return success if we at least cleaned the record
        fi

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
        [[ "$new_timeout" -eq 0 ]] ||
        [[ "$new_timeout" -gt 86400 ]]; then
        echo "Error: positive integer required (max 86400)." >&2
        return 1
    fi

    # Quick check for empty state
    if [[ ! -s "$HANDSSHAKE_RECORD_FILE" ]]; then
        echo "No keys currently recorded to update." >&2
        return 0
    fi

    # Acquire lock for record modification (Defense-in-depth)
    (
        flock -x 200

        echo "Updating timeout for all recorded keys to ${new_timeout}s..."
        local updated=0
        local failed=0

        # Get unique keys first (remove duplicates and empty lines)
        local unique_keys
        unique_keys=$(sort -u "$HANDSSHAKE_RECORD_FILE" | grep -v '^$')

        # Process keys
        while read -r key_file; do
            [[ -z "$key_file" ]] && continue

            local abs_key
            abs_key=$(readlink -f "$key_file" 2> /dev/null ||
                realpath "$key_file" 2> /dev/null ||
                echo "$key_file")

            if [[ -f "$abs_key" ]]; then
                # Detach first then re-attach with new timeout
                ssh-add -d "$abs_key" > /dev/null 2>&1 || true
                if ssh-add -t "$new_timeout" "$abs_key" > /dev/null 2>&1; then
                    updated=$((updated + 1))
                else
                    log_warn "Failed to update timeout for $abs_key."
                    failed=$((failed + 1))
                fi
            else
                log_warn "Key file not found during timeout update: $abs_key."
                failed=$((failed + 1))
            fi
        done <<< "$unique_keys"

        echo "Updated $updated keys."
        if [[ $failed -gt 0 ]]; then
            log_warn "Failed to update $failed recorded keys."
        fi
        log_info "Global timeout updated to ${new_timeout}s for $updated keys."
    ) 200> "$HANDSSHAKE_LOCK_FILE"

    return 0
}
