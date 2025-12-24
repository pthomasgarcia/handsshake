# shellcheck shell=bash

# This file contains shared setup, teardown, and helper functions
# for all handsshake BATS tests.

# Record the real HOME before we start mocking it
# This must be done at the top level to capture the actual environment
if [[ -z "${REAL_HOME_FOR_GUARD:-}" ]]; then
    export REAL_HOME_FOR_GUARD="$HOME"
fi

# Helper functions
create_test_key() {
    local key_path="$1"
    local comment="${2:-}"
    local -a key_args=()

    # Determine key type from filename pattern
    local base_name
    base_name=$(basename "$key_path")

    case "$base_name" in
    *ed25519*)
        key_args=(-t ed25519)
        ;;
    *ecdsa*)
        key_args=(-t ecdsa -b 521)
        ;;
    *rsa* | *)
        key_args=(-t rsa -b 2048)
        ;;
    esac

    if [[ -n "$comment" ]]; then
        ssh-keygen "${key_args[@]}" -f "$key_path" -N "" -C "$comment" >/dev/null 2>&1
    else
        ssh-keygen "${key_args[@]}" -f "$key_path" -N "" >/dev/null 2>&1
    fi
}

verify_agent_contains_key() {
    local key_comment="$1"
    if [[ -f "$STATE_DIR/ssh-agent.env" ]]; then
        source "$STATE_DIR/ssh-agent.env"
        run ssh-add -l
        assert_output --partial "$key_comment"
    fi
}

verify_agent_empty() {
    if [[ -f "$STATE_DIR/ssh-agent.env" ]]; then
        source "$STATE_DIR/ssh-agent.env"
        run ssh-add -l
        [[ "$status" -ne 0 ]]
    fi
}

verify_key_recorded() {
    local key_path="$1"
    run grep -Fq "$key_path" "$STATE_DIR/added_keys.list"
    assert_success
}

verify_key_not_recorded() {
    local key_path="$1"
    run grep -Fq "$key_path" "$STATE_DIR/added_keys.list"
    assert_failure
}

# Helper for permission tests
setup_readonly() {
    local path="$1"
    chmod 555 "$path"
}

teardown_readonly() {
    local path="$1"
    chmod 755 "$path" 2>/dev/null || true
}

# Setup function
setup() {
    # Create a temporary directory for the tests to run in.
    BATS_TMPDIR="$(mktemp -d -t handsshake-tests-XXXXXXXX)"

    # Use temporary HOME directory to avoid touching real files
    export HOME="$BATS_TMPDIR/home"

    # CRITICAL GUARD: Ensure we are not using the real HOME
    if [[ "$HOME" == "$REAL_HOME_FOR_GUARD" ]]; then
        echo "FATAL ERROR: HOME is not properly mocked! Isolation failed." >&2
        exit 1
    fi

    # Further safety check: ensure we are in a temporary location
    if [[ "$HOME" != *"/handsshake-tests-"* ]]; then
        echo "FATAL ERROR: HOME does not appear to be a test-specific directory!" >&2
        exit 1
    fi

    mkdir -p "$HOME/.ssh"

    # Setup XDG directories based on mocked HOME
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_STATE_HOME="$HOME/.local/state"

    # Define paths based on XDG standard as implemented in config.sh
    export CONFIG_DIR="$XDG_CONFIG_HOME/handsshake"
    export STATE_DIR="$XDG_STATE_HOME/handsshake"

    mkdir -p "$CONFIG_DIR"
    mkdir -p "$STATE_DIR"

    # The script to test
    HANDSSHAKE_SCRIPT="$BATS_TEST_DIRNAME/../src/core/main.sh"

    # Verify the script exists
    if [[ ! -f "$HANDSSHAKE_SCRIPT" ]]; then
        echo "ERROR: Script not found: $HANDSSHAKE_SCRIPT"
        exit 1
    fi

    # Source the script to load functions into the test scope
    local -a _bats_args=("$@")
    set --
    source "$HANDSSHAKE_SCRIPT"
    set -- "${_bats_args[@]}"

    # Pre-create and truncate the record file
    : >"$STATE_DIR/added_keys.list"
}

# Teardown function
teardown() {
    # Call cleanup function directly since we sourced the script
    if [[ -n "${HANDSSHAKE_LOADED:-}" ]]; then
        run main cleanup 2>/dev/null || true
    fi

    # Ensure cleanup even if script fails
    if [[ -n "${SSH_AGENT_PID:-}" ]]; then
        kill "$SSH_AGENT_PID" 2>/dev/null || true
        unset SSH_AGENT_PID
    fi

    # Kill any remaining external agents
    pkill -f "ssh-agent.*handsshake" 2>/dev/null || true

    # Cleanup temp directory
    if [[ -d "$BATS_TMPDIR" ]]; then
        rm -rf "$BATS_TMPDIR"
    fi
}
