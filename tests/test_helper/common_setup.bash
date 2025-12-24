# shellcheck shell=bash

# This file contains shared setup, teardown, and helper functions
# for all handsshake BATS tests.

# Record the real HOME before we start mocking it
if [[ -z "${REAL_HOME_FOR_GUARD:-}" ]]; then
    if command -v getent >/dev/null 2>&1; then
        REAL_HOME_FOR_GUARD=$(getent passwd "$(whoami)" | cut -d: -f6)
    fi
    : "${REAL_HOME_FOR_GUARD:=$(eval echo "~$(whoami)")}"
    export REAL_HOME_FOR_GUARD
fi

# Isolation guard function
check_isolation() {
    # 1. CRITICAL GUARD: Ensure we are not using the real HOME
    if [[ "$HOME" == "$REAL_HOME_FOR_GUARD" ]]; then
        echo "FATAL SECURITY ERROR: HOME is not properly mocked! Isolation failed." >&2
        echo "Current HOME: $HOME" >&2
        echo "Real HOME recorded: $REAL_HOME_FOR_GUARD" >&2
        return 1
    fi

    # 2. PATTERN GUARD: ensure we are in a temporary location
    if [[ "$HOME" != *"/handsshake-tests-"* ]]; then
        echo "FATAL SECURITY ERROR: HOME does not appear to be a test-specific directory!" >&2
        echo "Current HOME: $HOME" >&2
        return 1
    fi

    # 3. ROOT GUARD: Ensure we aren't at the system root
    if [[ "$HOME" == "/" ]] || [[ "$HOME" == "/root" ]] || [[ "$HOME" == "/home" ]]; then
        echo "FATAL SECURITY ERROR: HOME is pointing to a system directory!" >&2
        return 1
    fi

    return 0
}

# Helper functions
create_test_key() {
    local key_path="$1"
    local comment="${2:-}"
    local -a key_args=()

    # SECONDARY SAFETY GUARD: Never write to real HOME
    local resolved_path
    resolved_path=$(realpath "$key_path" 2>/dev/null || echo "$key_path")
    if [[ "$resolved_path" == "$REAL_HOME_FOR_GUARD"* ]]; then
        echo "FATAL SECURITY ERROR: create_test_key attempted to write to real HOME: $resolved_path" >&2
        exit 100
    fi
    
    # Path depth guard: ensure it's not a root-level or dangerously short path
    if [[ "$resolved_path" == "/etc/"* ]] || [[ "$resolved_path" == "/usr/"* ]] || [[ "$resolved_path" == "/var/"* ]]; then
        echo "FATAL SECURITY ERROR: create_test_key attempted to write to system directory: $resolved_path" >&2
        exit 102
    fi

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

generate_test_identity() {
    local slug="$1"
    local algo="${2:-rsa}"
    local comment="handsshake-test-$slug"
    
    # Policy-driven pathing: Use dedicated identities folder
    local identities_dir="$BATS_TMPDIR/identities"
    mkdir -p "$identities_dir"
    
    local key_path="$identities_dir/hsh-test-$slug-$algo.identity"
    create_test_key "$key_path" "$comment"
    
    echo "$key_path"
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

safe_cp() {
    local src="$1"
    local dest="$2"
    local resolved_dest
    resolved_dest=$(realpath "$dest" 2>/dev/null || echo "$dest")
    if [[ "$resolved_dest" == "$REAL_HOME_FOR_GUARD"* ]]; then
        echo "FATAL SECURITY ERROR: safe_cp attempted to write to real HOME: $resolved_dest" >&2
        exit 101
    fi
    cp "$src" "$dest"
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
    # 1. SCRUB ENVIRONMENT
    # Completely isolate from any existing SSH agent
    unset SSH_AUTH_SOCK
    unset SSH_AGENT_PID
    unset SSH_ASKPASS
    
    # 2. CREATE STRUCTURED VIRTUAL ROOT
    BATS_TMPDIR="$(mktemp -d -t handsshake-tests-XXXXXXXX)"
    
    # Use temporary HOME directory to avoid touching real files
    export HOME="$BATS_TMPDIR/mock-home"
    mkdir -p "$HOME/.ssh"

    if ! check_isolation; then
        exit 1
    fi

    # Setup XDG directories based on mocked HOME
    export XDG_CONFIG_HOME="$BATS_TMPDIR/config"
    export XDG_STATE_HOME="$BATS_TMPDIR/state"

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
