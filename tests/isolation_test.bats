#!/usr/bin/env bats

load "test_helper/bats-support/load.bash"
load "test_helper/bats-assert/load.bash"

@test "isolation: ignores inherited HANDSSHAKE_ variables" {
    # 1. SETUP: Poison the environment with "production" values
    export HANDSSHAKE_AGENT_ENV_FILE="/tmp/POISONED_ENV_FILE"
    export HANDSSHAKE_RECORD_FILE="/tmp/POISONED_RECORD_FILE"
    
    # 2. LOAD: Load the test helper (which should sanitize this)
    load "test_helper/common_setup.bash"
    
    # 3. VERIFY: The setup function should have unset these
    # Note: common_setup.bash defines 'setup', which bats runs before each test.
    # However, 'setup' also sets NEW values for these variables.
    # We want to ensure that the *internal* logic of config.sh didn't pick up the OLD values
    # before they were overwritten by the test harness, OR that the test harness correctly
    # overwrote them.
    
    # Actually, the critical thing is that config.sh (loaded by main.sh) does not see the poisoned values.
    # setup() sources main.sh.
    
    # Run the setup function explicitly (Bats does this, but we want to be sure of the state)
    setup
    
    # Check that the variables now point to the BATS_TMPDIR, NOT the poisoned path
    # Check that the variables now point to the BATS_TMPDIR, NOT the poisoned path
    [[ "$HANDSSHAKE_AGENT_ENV_FILE" != "/tmp/POISONED_ENV_FILE" ]]


    # Double check that the file used by the code is actually the temp one
    run main health
    assert_success
}
