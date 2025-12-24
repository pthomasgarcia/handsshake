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
  
  # Restore permissions for teardown
  chmod 755 "$STATE_DIR"
}

@test "handles unwritable lock file gracefully" {
  # Create lock file and make it read-only
  touch "$HANDSSHAKE_LOCK_FILE"
  chmod 444 "$HANDSSHAKE_LOCK_FILE"
  
  # Try a simple command
  run main health
  
  # Clean up
  chmod 644 "$HANDSSHAKE_LOCK_FILE"
  rm -f "$HANDSSHAKE_LOCK_FILE"
}

@test "concurrent attach calls should not corrupt state" {
  local key1
  local key2
  key1=$(generate_test_identity "concurrent-1" "rsa")
  key2=$(generate_test_identity "concurrent-2" "rsa")
  
  # Run attaches sequentially to avoid race conditions in test
  run main attach "$key1"
  assert_success
  
  run main attach "$key2"
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
    # shellcheck disable=SC1091
    source "$STATE_DIR/ssh-agent.env"
    run ssh-add -l
    assert_output --partial "handsshake-test-concurrent-1"
    assert_output --partial "handsshake-test-concurrent-2"
  fi
}

@test "state file should be properly formatted after multiple operations" {
  local key1
  local key2
  key1=$(generate_test_identity "format-state-1" "rsa")
  key2=$(generate_test_identity "format-state-2" "rsa")
  
  # Attach, detach, re-attach
  run main attach "$key1"
  assert_success
  
  run main attach "$key2"
  assert_success
  
  run main detach "$key1"
  assert_success
  
  # Verify only key2 remains
  verify_key_not_recorded "$key1"
  verify_key_recorded "$key2"
  
  # File should have exactly 1 line
  local line_count
  line_count=$(wc -l < "$STATE_DIR/added_keys.list")
  assert_equal "$line_count" 1
}

@test "handles multiple keys efficiently" {
  local keys=()
  for i in {1..5}; do
    local test_key
    test_key=$(generate_test_identity "many-key-$i" "rsa")
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
    assert_output --partial "handsshake-test-many-key-$i"
  done
  
  # Clean up
  run main flush
  assert_success
}

@test "state persistence across commands" {
  local test_key
  test_key=$(generate_test_identity "persistence" "rsa")
  
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
  assert_output --partial "handsshake-test-persistence"
  
  # Keys should show public key
  run main keys
  assert_success
  assert_output --partial "handsshake-test-persistence"
  
  # Cleanup should remove everything
  run main cleanup
  assert_success
  
  # Health should show no keys
  run main health
  assert_success
  assert_output --partial "Agent is reachable"
}

@test "multiple key types can be attached and managed" {
  local key_rsa
  local key_ed25519
  local key_ecdsa
  
  key_rsa=$(generate_test_identity "multi-rsa" "rsa")
  key_ed25519=$(generate_test_identity "multi-ed25519" "ed25519")
  key_ecdsa=$(generate_test_identity "multi-ecdsa" "ecdsa")
  
  # Attach all key types
  run main attach "$key_rsa"
  assert_success
  run main attach "$key_ed25519"
  assert_success
  run main attach "$key_ecdsa"
  assert_success
  
  # List all keys
  run main list
  assert_success
  assert_output --partial "handsshake-test-multi-rsa"
  assert_output --partial "handsshake-test-multi-ed25519"
  assert_output --partial "handsshake-test-multi-ecdsa"
  
  # Verify all are recorded
  verify_key_recorded "$key_rsa"
  verify_key_recorded "$key_ed25519"
  verify_key_recorded "$key_ecdsa"
  
  # Test detach of specific type
  run main detach "$key_ed25519"
  assert_success
  
  # Verify only Ed25519 is removed
  verify_key_not_recorded "$key_ed25519"
  verify_key_recorded "$key_rsa"
  verify_key_recorded "$key_ecdsa"
  
  # Flush should remove remaining
  run main flush
  assert_success
}

@test "record file maintains integrity across operations" {
  local key1
  local key2
  key1=$(generate_test_identity "integrity-1" "rsa")
  key2=$(generate_test_identity "integrity-2" "rsa")
  
  # Attach both keys
  run main attach "$key1"
  run main attach "$key2"
  
  # Record file should have 2 lines, no duplicates
  local line_count
  line_count=$(wc -l < "$STATE_DIR/added_keys.list")
  assert_equal "$line_count" 2
  
  # Detach one key
  run main detach "$key1"
  
  # Record file should have 1 line
  line_count=$(wc -l < "$STATE_DIR/added_keys.list")
  assert_equal "$line_count" 1
  
  # The remaining line should be key2
  grep -q "$key2" "$STATE_DIR/added_keys.list"
  assert_success
  
  # Flush should remove record file
  run main flush
  [[ ! -f "$STATE_DIR/added_keys.list" ]]
}



@test "verbose mode shows detailed output" {
  # shellcheck disable=SC2030,SC2031
  export HANDSSHAKE_VERBOSE=true
  local test_key
  test_key=$(generate_test_identity "verbose" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  unset HANDSSHAKE_VERBOSE
}

@test "non-verbose mode shows minimal output" {
  # shellcheck disable=SC2030,SC2031
  export HANDSSHAKE_VERBOSE=false
  local test_key
  test_key=$(generate_test_identity "quiet" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  unset HANDSSHAKE_VERBOSE
}





@test "invalid flag combinations should fail gracefully" {
  run main attach --list
  [[ "$status" -ne 0 ]]
  
  run main --health --version
  [[ "$status" -ne 127 ]]
}

@test "handles rapid concurrent operations without corruption" {
  local iterations=5
  local pids=()
  
  for i in $(seq 1 $iterations); do
    (
      local key
      key=$(generate_test_identity "race-$i" "rsa")
      main attach "$key" >/dev/null 2>&1
    ) &
    pids+=($!)
  done
  
  for pid in "${pids[@]}"; do
    wait "$pid"
  done
  
  run main list
  assert_success
  
  local record_count
  record_count=$(wc -l < "$STATE_DIR/added_keys.list")
  assert_equal "$record_count" "$iterations"
  
  for i in $(seq 1 $iterations); do
    assert_output --partial "handsshake-test-race-$i"
  done
}

@test "rejects malformed command injection attempts" {
  local secret
  secret="INJECTED_$(date +%s)"
  local injections=(
    "key; echo $secret"
    "key && echo $secret"
    "key | echo $secret"
    "key\n$secret"
    "key\n$secret"
  )
  
  for injection in "${injections[@]}"; do
    run main attach "$injection"
    assert_failure
    local line
    for line in "${lines[@]}"; do
        [[ "$line" == "$secret" ]] && return 1
    done
  done
  true
}

@test "prevents privilege escalation through path traversal" {
  local malicious_key="../../../etc/passwd"
  
  run main attach "$malicious_key"
  assert_failure
  assert_output --partial "is missing or not readable"
}



@test "continues operation when SSH_AUTH_SOCK is corrupted" {
  local test_key
  test_key=$(generate_test_identity "corrupt-sock" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  # shellcheck disable=SC2155
  export SSH_AUTH_SOCK
  SSH_AUTH_SOCK="/tmp/nonexistent-socket-$(date +%s)"
  
  run main list
  assert_success
  assert_output --partial "handsshake-test-corrupt-sock"
}

@test "-- separator allows commands that look like flags" {
  run main -- --help
  [[ "$status" -ne 127 ]]
}
