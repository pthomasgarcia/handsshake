#!/usr/bin/env bash
# src/services/keys.sh
# shellcheck shell=bash

# --- Dependencies ---
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../util/files.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../util/loggers.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../util/validators.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/agents.sh"

# --- Record Management (Internal) ---

keys::_record() {
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

keys::_detach_record() {
    local key_file="$1"
    if [[ -f "$HANDSSHAKE_RECORD_FILE" ]]; then
        local tmp_content
        tmp_content=$(grep -Fxv "$key_file" "$HANDSSHAKE_RECORD_FILE" || true)
        if [[ -z "$tmp_content" ]]; then
            rm -f "$HANDSSHAKE_RECORD_FILE"
        else
            files::atomic_write "$HANDSSHAKE_RECORD_FILE" "$tmp_content"
        fi
    fi
}

keys::_clear_records() {
    if [[ -f "$HANDSSHAKE_RECORD_FILE" ]]; then
        rm -f "$HANDSSHAKE_RECORD_FILE"
    fi
}

# --- Key Information ---

keys::_get_fingerprint() {
    local key_file="$1"
    if [[ "$key_file" =~ \.\.[\\/] ]] || [[ "$key_file" =~ ^~[^/] ]]; then
        loggers::error "Invalid key file path: $key_file"
        return 1
    fi

    local fingerprint
    fingerprint=$(ssh-keygen -lf "$key_file" 2> /dev/null | awk '{print $2}')
    if [[ -n "$fingerprint" ]]; then
        echo "$fingerprint"
        return 0
    fi

    return 1
}

# --- Primary Service Commands ---

# Usage: attach [key_file]
keys::attach() {
    agents::ensure
    local key_file="${1:-$HANDSSHAKE_DEFAULT_KEY}"

    if [[ "$key_file" == "$HANDSSHAKE_DEFAULT_KEY" ]] && [[ -z "${1:-}" ]]; then
        echo "No key specified. Using default: $key_file"
    fi

    if ! validators::file "$key_file" "r" 2> /dev/null; then
        echo "Invalid key file: '$key_file' is missing or not readable." >&2
        return 1
    fi

    # Verify it's a valid SSH key and get fingerprint
    local fingerprint
    if ! fingerprint=$(keys::_get_fingerprint "$key_file"); then
        echo "Invalid key file: '$key_file' is not a valid SSH key." >&2
        return 1
    fi

    # Check if key is already in agent (avoid duplicate attach)
    if ssh-add -l 2> /dev/null | grep -q "$fingerprint"; then
        loggers::info "Key '$key_file' already in agent (fingerprint: \
$fingerprint)."
        echo "Key '$key_file' already attached."
        keys::_record "$key_file"
        return 0
    fi

    echo "Attaching key '$key_file'..."
    if ssh-add -t "$HANDSSHAKE_DEFAULT_TIMEOUT" "$key_file"; then
        loggers::info "Key '$key_file' attached \
(timeout: ${HANDSSHAKE_DEFAULT_TIMEOUT}s)."
        echo "Key '$key_file' attached."
        keys::_record "$key_file"
    else
        loggers::error "Failed to attach key '$key_file'."
        return 1
    fi
}

# Usage: detach <key_file>
keys::detach() {
    agents::ensure
    local key_file="${1:-}"

    if [[ -z "$key_file" ]] || [[ "$#" -ne 1 ]]; then
        echo "Error: detach requires exactly one fingerprint/key_file." >&2
        return 1
    fi

    # We attempt to detach from the agent even if the file is missing locally
    echo "Detaching key '$key_file'..."
    if ssh-add -d "$key_file" 2> /dev/null; then
        loggers::info "Detached key '$key_file' from agent."
        echo "Key '$key_file' detached."
    else
        # If it failed, it might be because the file is missing,
        # but we should still check if it was in our record
        if [[ -f "$HANDSSHAKE_RECORD_FILE" ]] &&
            grep -Fxq "$key_file" "$HANDSSHAKE_RECORD_FILE"; then
            loggers::warn "Key '$key_file' file missing but was in record. \
Cleaning up record."
            echo "Key '$key_file' detached."
            keys::_detach_record "$key_file"
            return 0 # Return success if we at least cleaned the record
        fi

        loggers::warn "Key '$key_file' was not in the agent or file missing."
        echo "Warning: Key '$key_file' not found in agent." >&2
        keys::_detach_record "$key_file"
        return 1
    fi

    # Always clean the record to maintain consistency
    keys::_detach_record "$key_file"
}

# Usage: flush
keys::flush() {
    agents::ensure
    echo "Flushing all keys from agent..."
    if ssh-add -D; then
        loggers::info "Flushed all keys from ssh-agent."
        echo "All keys flushed."
        keys::_clear_records
    else
        loggers::error "Failed to flush keys."
        return 1
    fi
}

# Usage: list
keys::list() {
    agents::ensure
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

# Usage: export
# Maps to export|-e|--export) export "$@" ;;
keys::export() {
    agents::ensure
    ssh-add -L
}

# Usage: timeout <seconds> <key_file> (Single)
#        timeout --all <seconds> (Global)

# Internal: Update Global Timeout
keys::update_timeouts() {
    agents::ensure
    local new_timeout="${1:-}"

    if [[ -z "$new_timeout" ]]; then
        loggers::error "timeout --all requires exactly one argument (seconds)."
        return 1
    fi

    if ! validators::int_constraints "$new_timeout" "1" "86400" "false"; then
        return 1
    fi

    # Quick check for empty state
    if [[ ! -s "$HANDSSHAKE_RECORD_FILE" ]]; then
        echo "No keys currently recorded to update." >&2
        return 0
    fi

    # Acquire lock for record modification (Defense-in-depth)
    files::lock "$HANDSSHAKE_LOCK_FILE" \
        keys::_perform_refresh "$new_timeout"

    return 0
}

keys::_perform_refresh() {
    local new_timeout="$1"
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
                loggers::warn "Failed to update timeout for $abs_key."
                failed=$((failed + 1))
            fi
        else
            loggers::warn "Key file not found during timeout update: \
$abs_key."
            failed=$((failed + 1))
        fi
    done <<< "$unique_keys"

    echo "Updated $updated keys."
    if [[ $failed -gt 0 ]]; then
        loggers::warn "Failed to update $failed recorded keys."
    fi
    loggers::info "Global timeout updated to ${new_timeout}s for \
$updated keys."
}

# Usage: timeout <key_file> <seconds>
keys::update_timeout() {
    agents::ensure
    local key_file="${1:-}"
    local new_timeout="${2:-}"

    if [[ -z "$key_file" ]] || [[ -z "$new_timeout" ]]; then
        loggers::error "Usage: timeout <key_file> <seconds>"
        return 1
    fi

    if ! validators::int_constraints "$new_timeout" "1" "86400" "false"; then
        return 1
    fi

    if ! validators::file "$key_file" "r" 2> /dev/null; then
        loggers::error "Invalid key file: '$key_file'"
        return 1
    fi

    # Detach and Re-attach with new timeout
    if ssh-add -d "$key_file" > /dev/null 2>&1; then
        # Key was attached, now re-attach
        if ssh-add -t "$new_timeout" "$key_file"; then
            loggers::info "Updated timeout for '$key_file' to ${new_timeout}s."
            echo "Timeout updated."
            keys::_record "$key_file"
        else
            loggers::error "Failed to re-attach '$key_file' with new timeout."
            return 1
        fi
    else
        # Key wasn't meant to be updated or wasn't attached.
        echo "Key wasn't attached. Attaching now..."
        if ssh-add -t "$new_timeout" "$key_file"; then
            loggers::info "Attached '$key_file' with timeout ${new_timeout}s."
            echo "Key attached with timeout."
            keys::_record "$key_file"
        else
            loggers::error "Failed to attach '$key_file'."
            return 1
        fi
    fi
    return 0
}
