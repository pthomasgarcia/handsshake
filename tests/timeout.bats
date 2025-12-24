#!/usr/bin/env bats

load "test_helper/bats-support/load.bash"
load "test_helper/bats-assert/load.bash"
load "test_helper/common_setup.bash"

@test "timeout command should update timeouts" {
  local test_key
  test_key=$(generate_test_identity "timeout-basic" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  run main timeout 1800
  assert_success
  assert_output --partial "Updated 1 keys."
}

@test "timeout with -t flag works" {
  local test_key
  test_key=$(generate_test_identity "timeout-t" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  run main -t 1800
  assert_success
  assert_output --partial "Updated 1 keys."
}

@test "timeout with --timeout flag works" {
  local test_key
  test_key=$(generate_test_identity "timeout-flag" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  run main --timeout 1800
  assert_success
  assert_output --partial "Updated 1 keys."
}

@test "timeout updates all keys correctly" {
  local key1
  local key2
  key1=$(generate_test_identity "timeout-batch-1" "rsa")
  key2=$(generate_test_identity "timeout-batch-2" "rsa")
  
  run main attach "$key1"
  assert_success
  run main attach "$key2"
  assert_success
  
  # Update timeouts
  run main timeout 3600
  assert_success
  assert_output --partial "Updated 2 keys"
  
  # Verify both still exist in agent
  run main list
  assert_output --partial "handsshake-test-timeout-batch-1"
  assert_output --partial "handsshake-test-timeout-batch-2"
}

@test "timeout with invalid value should fail" {
  run main timeout -5
  assert_failure
  assert_output --partial "positive integer required"
  
  run main timeout "not_a_number"
  assert_failure
  assert_output --partial "integer required"
}

@test "timeout without argument should fail" {
  run main timeout
  assert_failure
  assert_output --partial "requires exactly one argument"
}

@test "timeout with empty record file" {
  # Ensure record file is empty
  : > "$STATE_DIR/added_keys.list"
  
  run main timeout 3600
  assert_success
  assert_output --partial "No keys currently recorded to update"
}

@test "timeout with some keys missing" {
  local key1
  local key2
  key1=$(generate_test_identity "timeout-missing-1" "rsa")
  key2=$(generate_test_identity "timeout-missing-2" "rsa")
  
  run main attach "$key1"
  assert_success
  run main attach "$key2"
  assert_success
  
  # Remove one key file
  rm -f "$key2"
  
  run main timeout 1800
  assert_success
  # Should report 1 key updated (key1)
  assert_output --partial "Updated 1 keys"
}

@test "timeout handles boundary values correctly" {
  local test_key
  test_key=$(generate_test_identity "timeout-boundary" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  # Test minimum reasonable timeout (1 second)
  run main timeout 1
  assert_success
  
  # Test maximum allowed timeout (86400 seconds = 1 day)
  run main timeout 86400
  assert_success
  
  # Test just over maximum should fail
  run main timeout 86401
  assert_failure
  assert_output --partial "max 86400"
  
  # Test zero should fail (needs positive integer)
  run main timeout 0
  assert_failure
  assert_output --partial "positive integer"
}
