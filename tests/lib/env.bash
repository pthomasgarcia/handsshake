# shellcheck shell=bash

# tests/lib/env.bash
# Handles environment setup, isolation guarding, and variable scrubbing

init_env() {
    # Record the real HOME before we start mocking it
    if [[ -z "${REAL_HOME_FOR_GUARD:-}" ]]; then
        if command -v getent >/dev/null 2>&1; then
            REAL_HOME_FOR_GUARD=$(getent passwd "$(whoami)" | cut -d: -f6)
        fi
        : "${REAL_HOME_FOR_GUARD:=$(eval echo "~$(whoami)")}"
        export REAL_HOME_FOR_GUARD
    fi
}

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

setup_test_env() {
    # 1. SCRUB ENVIRONMENT
    # Completely isolate from any existing SSH agent
    unset SSH_AUTH_SOCK
    unset SSH_AGENT_PID
    unset SSH_ASKPASS

    # CRITICAL: Dynamic Unset of all HANDSSHAKE_ variables
    # This loop finds all variables starting with HANDSSHAKE_ and unsets them.
    # Note: Bash 4.4+ is assumed for ${!prefix@} expansion, which is standard on most linux systems.
    # If not available, we fall back to manual list (but here we assume modern environment).
    for var in ${!HANDSSHAKE_@}; do
        unset "$var"
    done
    
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
    # We use BATS_TEST_DIRNAME relative to this file's usage location? 
    # Actually BATS_TEST_DIRNAME is where the test file is.
    # We assume tests are in tests/ or tests/integration/.
    # Safe bet is specific relative path or finding it.
    # Assuming standard project structure:
    # If test is in tests/, src is ../src
    # If test is in tests/integration/, src is ../../src
    # Let's try to locate it dynamically or assume simpler structure for now.
    
    # Simple relative path assumption based on current location of tests
    if [[ -f "$BATS_TEST_DIRNAME/../src/core/main.sh" ]]; then
        HANDSSHAKE_SCRIPT="$BATS_TEST_DIRNAME/../src/core/main.sh"
    elif [[ -f "$BATS_TEST_DIRNAME/../../src/core/main.sh" ]]; then
        HANDSSHAKE_SCRIPT="$BATS_TEST_DIRNAME/../../src/core/main.sh"
    else
         # Fallback to absolute assumption if relative fails
         HANDSSHAKE_SCRIPT="$(git rev-parse --show-toplevel 2>/dev/null)/src/core/main.sh"
    fi

    export HANDSSHAKE_SCRIPT

    # Verify the script exists
    if [[ ! -f "$HANDSSHAKE_SCRIPT" ]]; then
        echo "ERROR: Script not found: $HANDSSHAKE_SCRIPT"
        exit 1
    fi

    # Source the script to load functions into the test scope
    # We use a trick to preserve $@ for bats
    local -a _bats_args=("$@")
    set --
    # shellcheck source=/dev/null
    source "$HANDSSHAKE_SCRIPT"
    set -- "${_bats_args[@]}"

    # Pre-create and truncate the record file
    : >"$STATE_DIR/added_keys.list"
}

teardown_test_env() {
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
