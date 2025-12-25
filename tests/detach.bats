#!/usr/bin/env bats

load "test_helper"

@test "detach command should remove a key" {
  local test_key
  test_key=$(generate_test_identity "basic-detach" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  run main detach "$test_key"
  assert_success
  assert_output --partial "Key '$test_key' detached"
  
  verify_key_not_recorded "$test_key"
  verify_agent_empty
}

@test "detach with -d flag works" {
  local test_key
  test_key=$(generate_test_identity "flag-d" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  run main -d "$test_key"
  assert_success
  assert_output --partial "Key '$test_key' detached"
  
  verify_key_not_recorded "$test_key"
  verify_agent_empty
}

@test "detach with --detach flag works" {
  local test_key
  test_key=$(generate_test_identity "flag-detach" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  run main --detach "$test_key"
  assert_success
  assert_output --partial "Key '$test_key' detached"
  
  verify_key_not_recorded "$test_key"
  verify_agent_empty
}

@test "detach non-attached key should fail" {
  local test_key
  test_key=$(generate_test_identity "not-attached" "rsa")
  
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
  local test_key
  test_key=$(generate_test_identity "missing-file" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  # Remove the key file but keep it in agent/record
  rm -f "$test_key" "$test_key.pub"
  
  run main detach "$test_key"
  # Should succeed in removing from record even if file missing
  assert_success
  assert_output --partial "detached"
  
  verify_key_not_recorded "$test_key"
}

@test "detach with relative path" {
  local identities_dir="$BATS_TMPDIR/identities"
  mkdir -p "$identities_dir"
  local test_key="$identities_dir/hsh-test-relative.identity"
  create_test_key "$test_key" "relative-test"
  
  # Change to identities directory and use relative path
  (
      cd "$identities_dir" || exit 1
      run main attach "./hsh-test-relative.identity"
      assert_success
      
      run main detach "./hsh-test-relative.identity"
      assert_success
  )
}

@test "detach with stale record (key in record but not agent)" {
  local test_key
  test_key=$(generate_test_identity "stale-record" "rsa")
  
  # Manually add to record file without adding to agent
  echo "$test_key" >> "$STATE_DIR/added_keys.list"
  
  run main detach "$test_key"
  # Should succeed because it successfully "healed" the record state
  assert_success
  assert_output --partial "detached"
  
  verify_key_not_recorded "$test_key"
}

@test "detach preserves agent state for remaining keys" {
  local key1
  local key2
  key1=$(generate_test_identity "preserve-1" "rsa")
  key2=$(generate_test_identity "preserve-2" "rsa")
  
  run main attach "$key1"
  assert_success
  run main attach "$key2"
  assert_success
  
  # Detach only first key
  run main detach "$key1"
  assert_success
  
  # Verify second key remains in agent and records
  verify_agent_contains_key "handsshake-test-preserve-2"
  verify_key_recorded "$key2"
  
  # Verify first key is gone from both
  run ssh-add -l
  refute_output --partial "handsshake-test-preserve-1"
  verify_key_not_recorded "$key1"
}

@test "detach handles sequential operations safely" {
  local key1
  local key2
  key1=$(generate_test_identity "seq-1" "rsa")
  key2=$(generate_test_identity "seq-2" "rsa")
  
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
  run main detach "$BATS_TMPDIR/identities/nonexistent.identity"
  
  assert_failure
  assert_output --partial "not found in agent"
}

@test "detach with multiple arguments should fail" {
  local key1
  local key2
  key1=$(generate_test_identity "multi-detach-1" "rsa")
  key2=$(generate_test_identity "multi-detach-2" "rsa")
  
  run main detach "$key1" "$key2"
  assert_failure
  assert_output --partial "requires exactly one fingerprint"
}
