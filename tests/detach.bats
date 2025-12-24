#!/usr/bin/env bats

load "test_helper/bats-support/load.bash"
load "test_helper/bats-assert/load.bash"
load "test_helper/common_setup.bash"

@test "detach command should remove a key" {
  local test_key="$BATS_TMPDIR/test_detach_key_rsa"
  create_test_key "$test_key" "test_detach_key"
  
  run main attach "$test_key"
  assert_success
  
  run main detach "$test_key"
  assert_success
  assert_output --partial "Key '$test_key' detached"
  
  verify_key_not_recorded "$test_key"
  verify_agent_empty
}

@test "detach with -d flag works" {
  local test_key="$BATS_TMPDIR/test_d_flag_rsa"
  create_test_key "$test_key" "test_d_flag"
  
  run main attach "$test_key"
  assert_success
  
  run main -d "$test_key"
  assert_success
  assert_output --partial "Key '$test_key' detached"
  
  verify_key_not_recorded "$test_key"
  verify_agent_empty
}

@test "detach with --detach flag works" {
  local test_key="$BATS_TMPDIR/test_detach_flag_rsa"
  create_test_key "$test_key" "test_detach_flag"
  
  run main attach "$test_key"
  assert_success
  
  run main --detach "$test_key"
  assert_success
  assert_output --partial "Key '$test_key' detached"
  
  verify_key_not_recorded "$test_key"
  verify_agent_empty
}

@test "detach non-attached key should fail" {
  local test_key="$BATS_TMPDIR/test_not_attached_rsa"
  create_test_key "$test_key"
  
  run main detach "$test_key"
  
  assert_failure
  assert_output --partial "not found"
}

@test "detach without argument should fail" {
  run main detach
  
  assert_failure
  assert_output --partial "requires exactly one fingerprint"
}

@test "detach with missing key file should clean record" {
  local test_key="$BATS_TMPDIR/missing_key_rsa"
  create_test_key "$test_key" "test_missing_key"
  
  run main attach "$test_key"
  assert_success
  
  # Remove the key file but keep it in agent/record
  rm -f "$test_key" "$test_key.pub"
  
  run main detach "$test_key"
  # Should succeed in removing from agent/record even if file missing
  assert_success
  assert_output --partial "Key '$test_key' detached"
  
  verify_key_not_recorded "$test_key"
}

@test "detach with relative path" {
  local test_key="$BATS_TMPDIR/relative_key_rsa"
  create_test_key "$test_key" "relative_test"
  
  # Change to temp directory and use relative path
  cd "$BATS_TMPDIR"
  run main attach "./relative_key_rsa"
  assert_success
  
  run main detach "./relative_key_rsa"
  assert_success
  
  # Change back to original directory
  cd - > /dev/null
}

@test "detach with stale record (key in record but not agent)" {
  local test_key="$BATS_TMPDIR/stale_record_key_rsa"
  create_test_key "$test_key" "stale_record_test"
  
  # Manually add to record file without adding to agent
  echo "$test_key" >> "$STATE_DIR/added_keys.list"
  
  run main detach "$test_key"
  # Should succeed because it successfully "healed" the record state
  assert_success
  assert_output --partial "detached"
  
  verify_key_not_recorded "$test_key"
}

@test "detach preserves agent state for remaining keys" {
  local key1="$BATS_TMPDIR/preserve1_rsa"
  local key2="$BATS_TMPDIR/preserve2_rsa"
  
  create_test_key "$key1" "preserve_test_1"
  create_test_key "$key2" "preserve_test_2"
  
  run main attach "$key1"
  assert_success
  run main attach "$key2"
  assert_success
  
  # Detach only first key
  run main detach "$key1"
  assert_success
  
  # Verify second key remains in agent and records
  verify_agent_contains_key "preserve_test_2"
  verify_key_recorded "$key2"
  
  # Verify first key is gone from both
  run ssh-add -l
  refute_output --partial "preserve_test_1"
  verify_key_not_recorded "$key1"
}

@test "detach handles sequential operations safely" {
  local key1="$BATS_TMPDIR/seq1_rsa"
  local key2="$BATS_TMPDIR/seq2_rsa"
  
  create_test_key "$key1" "seq1"
  create_test_key "$key2" "seq2"
  
  run main attach "$key1"
  run main attach "$key2"
  
  # Detach both keys in sequence
  run main detach "$key1"
  assert_success
  run main detach "$key2"
  assert_success
  
  # Verify clean state
  verify_agent_empty
  [ ! -f "$STATE_DIR/added_keys.list" ]
}

@test "detach provides clear error for invalid key path" {
  # Detach a path that exists neither in agent nor in records
  run main detach "/nonexistent/path/to/key"
  
  assert_failure
  assert_output --partial "not found in agent"
}
