#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

load "test_helper/bats-support/load.bash"
load "test_helper/bats-assert/load.bash"

# We source the helper but then IMMEDIATELY override setup/teardown
# to prevent BATS from using the ones in common_setup.bash for these tests.
source "tests/test_helper/common_setup.bash"

setup() { :; }
teardown() { :; }

@test "isolation guard prevents real HOME usage" {
    # Mock current HOME to match the REAL_HOME_FOR_GUARD
    export HOME="$REAL_HOME_FOR_GUARD"
    
    run check_isolation
    assert_failure
    assert_output --partial "FATAL SECURITY ERROR: HOME is not properly mocked"
}

@test "isolation guard detects non-test temporary directory" {
    # Ensure REAL_HOME_FOR_GUARD is different so we pass the first check
    export REAL_HOME_FOR_GUARD="/some/other/home"
    
    # Set HOME to a path that doesn't match the required pattern
    export HOME="/tmp/unsafe-directory/home"
    
    run check_isolation
    assert_failure
    assert_output --partial \
        "HOME does not appear to be a test-specific directory"
}

@test "isolation guard passes with correct temporary directory" {
    export REAL_HOME_FOR_GUARD="/home/user"
    
    # Set HOME to a path that matches the pattern
    export HOME="/tmp/handsshake-tests-12345678/home"
    
    run check_isolation
    assert_success
}
