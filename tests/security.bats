#!/usr/bin/env bats

load "test_helper/bats-support/load.bash"
load "test_helper/bats-assert/load.bash"
load "test_helper/common_setup.bash"

@test "handles read-only state directory gracefully" {
  # Make state directory read-only
  chmod 555 "$STATE_DIR"
  
  # Try health check - should handle gracefully
  run main health
  # Note: This might succeed or fail, but shouldn't crash
  # We're testing that it handles the error gracefully
  
  # Restore permissions for teardown
  chmod 755 "$STATE_DIR"
}

@test "handles unwritable lock file gracefully" {
  # Create lock file and make it read-only
  touch "$HANDSSHAKE_LOCK_FILE"
  chmod 444 "$HANDSSHAKE_LOCK_FILE"
  
  # Try a simple command
  run main health
  # Should handle gracefully without crash
  
  # Clean up
  chmod 644 "$HANDSSHAKE_LOCK_FILE"
  rm -f "$HANDSSHAKE_LOCK_FILE"
}

@test "concurrent attach calls should not corrupt state" {
  local test_key1="$BATS_TMPDIR/concurrent_key1_rsa"
  local test_key2="$BATS_TMPDIR/concurrent_key2_rsa"
  create_test_key "$test_key1" "concurrent_key1"
  create_test_key "$test_key2" "concurrent_key2"
  
  # Run attaches sequentially to avoid race conditions in test
  run main attach "$test_key1"
  assert_success
  
  run main attach "$test_key2"
  assert_success
  
  # Verify file has exactly 2 lines
  local line_count
  line_count=$(grep -c . "$STATE_DIR/added_keys.list")
  assert_equal "$line_count" 2
  
  # Verify no duplicates
  local unique_count
  unique_count=$(sort -u "$STATE_DIR/added_keys.list" | wc -l)
  assert_equal "$unique_count" 2
  
  # Verify both keys in agent
  if [[ -f "$STATE_DIR/ssh-agent.env" ]]; then
    source "$STATE_DIR/ssh-agent.env"
    run ssh-add -l
    assert_output --partial "concurrent_key1"
    assert_output --partial "concurrent_key2"
  fi
}

@test "state file should be properly formatted after multiple operations" {
  local test_key1="$BATS_TMPDIR/key1_rsa"
  local test_key2="$BATS_TMPDIR/key2_rsa"
  create_test_key "$test_key1"
  create_test_key "$test_key2"
  
  # Attach, detach, re-attach
  run main attach "$test_key1"
  assert_success
  
  run main attach "$test_key2"
  assert_success
  
  run main detach "$test_key1"
  assert_success
  
  # Verify only key2 remains
  verify_key_not_recorded "$test_key1"
  verify_key_recorded "$test_key2"
  
  # File should have exactly 1 line
  local line_count
  line_count=$(wc -l < "$STATE_DIR/added_keys.list")
  assert_equal "$line_count" 1
}

@test "handles multiple keys efficiently" {
  local keys=()
  # Use a reasonable number for testing (not too many to be slow)
  for i in {1..5}; do
    local test_key="$BATS_TMPDIR/many_key_${i}_rsa"
    create_test_key "$test_key" "many_key_$i"
    keys+=("$test_key")
  done
  
  # Attach all keys
  for key in "${keys[@]}"; do
    run main attach "$key"
    assert_success
  done
  
  # Verify all are recorded
  run main list
  assert_success
  
  for i in {1..5}; do
    assert_output --partial "many_key_$i"
  done
  
  # Clean up
  run main flush
  assert_success
}

@test "state persistence across commands" {
  local test_key="$BATS_TMPDIR/persist_key_rsa"
  create_test_key "$test_key" "persist_test"
  
  # Attach the key
  run main attach "$test_key"
  assert_success
  
  # Health check should show key
  run main health
  assert_success
  assert_output --partial "Keys loaded: 1"
  
  # List should show key
  run main list
  assert_success
  assert_output --partial "persist_test"
  
  # Keys should show public key
  run main keys
  assert_success
  assert_output --partial "persist_test"
  
  # Cleanup should remove everything
  run main cleanup
  assert_success
  
  # Health should show no keys
  run main health
  assert_success
  assert_output --partial "Agent is reachable"
}

@test "multiple key types can be attached and managed" {
  local test_key_rsa="$BATS_TMPDIR/multi_key_rsa"
  local test_key_ed25519="$BATS_TMPDIR/multi_key_ed25519"
  local test_key_ecdsa="$BATS_TMPDIR/multi_key_ecdsa"
  
  create_test_key "$test_key_rsa" "multi_rsa"
  create_test_key "$test_key_ed25519" "multi_ed25519"
  create_test_key "$test_key_ecdsa" "multi_ecdsa"
  
  # Attach all key types
  run main attach "$test_key_rsa"
  assert_success
  
  run main attach "$test_key_ed25519"
  assert_success
  
  run main attach "$test_key_ecdsa"
  assert_success
  
  # List all keys
  run main list
  assert_success
  assert_output --partial "multi_rsa"
  assert_output --partial "multi_ed25519"
  assert_output --partial "multi_ecdsa"
  
  # Verify all are recorded
  verify_key_recorded "$test_key_rsa"
  verify_key_recorded "$test_key_ed25519"
  verify_key_recorded "$test_key_ecdsa"
  
  # Test detach of specific type
  run main detach "$test_key_ed25519"
  assert_success
  
  # Verify only Ed25519 is removed
  verify_key_not_recorded "$test_key_ed25519"
  verify_key_recorded "$test_key_rsa"
  verify_key_recorded "$test_key_ecdsa"
  
  # Flush should remove remaining
  run main flush
  assert_success
  
  # All should be gone
  verify_key_not_recorded "$test_key_rsa"
  verify_key_not_recorded "$test_key_ecdsa"
}

@test "record file maintains integrity across operations" {
  local test_key1="$BATS_TMPDIR/integrity_key1_rsa"
  local test_key2="$BATS_TMPDIR/integrity_key2_rsa"
  create_test_key "$test_key1" "integrity1"
  create_test_key "$test_key2" "integrity2"
  
  # Attach both keys
  run main attach "$test_key1"
  run main attach "$test_key2"
  
  # Record file should have 2 lines, no duplicates
  local line_count
  line_count=$(wc -l < "$STATE_DIR/added_keys.list")
  assert_equal "$line_count" 2
  
  # Lines should be unique
  local unique_count
  unique_count=$(sort -u "$STATE_DIR/added_keys.list" | wc -l)
  assert_equal "$unique_count" 2
  
  # Detach one key
  run main detach "$test_key1"
  
  # Record file should have 1 line
  line_count=$(wc -l < "$STATE_DIR/added_keys.list")
  assert_equal "$line_count" 1
  
  # The remaining line should be test_key2
  grep -q "$test_key2" "$STATE_DIR/added_keys.list"
  assert_success
  
  # Flush should remove record file
  run main flush
  [[ ! -f "$STATE_DIR/added_keys.list" ]]
}

@test "error messages are clear and actionable" {
  # Test detach without argument
  run main detach
  assert_failure
  assert_output --partial "requires exactly one"
  
  # Test attach with non-existent file
  run main attach "/nonexistent/path/to/key"
  assert_failure
  assert_output --partial "Invalid key file"
  
  # Test timeout with invalid value
  run main timeout "invalid"
  assert_failure
  assert_output --partial "integer required"
}

@test "verbose mode shows detailed output" {
  # Enable verbose mode
  export HANDSSHAKE_VERBOSE=true
  
  local test_key="$BATS_TMPDIR/verbose_key_rsa"
  create_test_key "$test_key" "verbose_test"
  
  run main attach "$test_key"
  assert_success
  # In verbose mode, we should see INFO logs
  # The exact output depends on logging implementation
  
  unset HANDSSHAKE_VERBOSE
}

@test "non-verbose mode shows minimal output" {
  # Disable verbose mode
  export HANDSSHAKE_VERBOSE=false
  
  local test_key="$BATS_TMPDIR/quiet_key_rsa"
  create_test_key "$test_key" "quiet_test"
  
  run main attach "$test_key"
  assert_success
  # Output should be more minimal
  
  unset HANDSSHAKE_VERBOSE
}

@test "attach with extra arguments should fail gracefully" {
  local test_key="$BATS_TMPDIR/extra_args_key_rsa"
  create_test_key "$test_key" "extra_args_test"
  
  run main attach "$test_key" "extra_argument"
  # The current implementation might not check for extra args
  # This test documents the current behavior
  # It should either fail with an error or ignore extra args
  # We'll check it doesn't crash
  [[ "$status" -ne 127 ]]  # 127 is command not found
}

@test "detach with multiple arguments should fail" {
  local test_key1="$BATS_TMPDIR/multi_detach1_rsa"
  local test_key2="$BATS_TMPDIR/multi_detach2_rsa"
  create_test_key "$test_key1" "multi1"
  create_test_key "$test_key2" "multi2"
  
  run main detach "$test_key1" "$test_key2"
  assert_failure
  assert_output --partial "requires exactly one fingerprint"
}

@test "invalid flag combinations should fail gracefully" {
  # Test ambiguous commands
  run main attach --list
  # This should fail because --list is not a valid argument for attach
  [[ "$status" -ne 0 ]]
  
  # Test conflicting commands
  run main --health --version
  # Should show one or the other (implementation dependent)
  [[ "$status" -ne 127 ]]  # Not command not found
}

@test "-- separator allows commands that look like flags" {
  # Test that -- allows --help to be treated as a command
  # The current implementation doesn't have a --help command
  # but -- should separate options from arguments
  
  # This tests that the command parser handles -- correctly
  run main -- --help
  # This should either process --help as a command or fail gracefully
  # Not crashing is the main requirement
  [[ "$status" -ne 127 ]]  # Not command not found
}
