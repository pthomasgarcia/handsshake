#!/usr/bin/env bats

load "test_helper/bats-support/load.bash"
load "test_helper/bats-assert/load.bash"
load "test_helper/common_setup.bash"

@test "flush command should remove all keys" {
  local test_key1="$BATS_TMPDIR/test_key1_rsa"
  local test_key2="$BATS_TMPDIR/test_key2_rsa"
  create_test_key "$test_key1" "key1"
  create_test_key "$test_key2" "key2"
  
  run main attach "$test_key1"
  run main attach "$test_key2"
  
  run main flush
  assert_success
  assert_output --partial "All keys flushed"
  
  [[ ! -f "$STATE_DIR/added_keys.list" ]]
  verify_agent_empty
}

@test "flush with -f flag works" {
  local test_key="$BATS_TMPDIR/test_f_flag_rsa"
  create_test_key "$test_key" "test_f_flag"
  
  run main attach "$test_key"
  assert_success
  
  run main -f
  assert_success
  assert_output --partial "All keys flushed"
  
  [[ ! -f "$STATE_DIR/added_keys.list" ]]
  verify_agent_empty
}

@test "flush with --flush flag works" {
  local test_key="$BATS_TMPDIR/test_flush_flag_rsa"
  create_test_key "$test_key" "test_flush_flag"
  
  run main attach "$test_key"
  assert_success
  
  run main --flush
  assert_success
  assert_output --partial "All keys flushed"
  
  [[ ! -f "$STATE_DIR/added_keys.list" ]]
  verify_agent_empty
}

@test "flush with no keys attached should succeed" {
  run main flush
  
  assert_success
  assert_output --partial "All keys flushed"
}

@test "flush when agent is not running" {
  # Clean up any existing agent
  run main cleanup
  assert_success
  
  # Remove environment file to simulate missing agent
  rm -f "$STATE_DIR/ssh-agent.env"
  
  run main flush
  # Should start agent and then flush (which will be empty)
  assert_success
}

@test "flush with corrupted record file" {
  # Create a corrupted record file
  echo "not a valid path" > "$STATE_DIR/added_keys.list"
  echo "/nonexistent/file" >> "$STATE_DIR/added_keys.list"
  echo "$HOME/.ssh/nonexistent_key" >> "$STATE_DIR/added_keys.list"
  
  run main flush
  assert_success
  assert_output --partial "All keys flushed"
  
  # Record file should be removed
  [[ ! -f "$STATE_DIR/added_keys.list" ]]
}

@test "list command shows attached keys" {
  local test_key="$BATS_TMPDIR/test_list_key_rsa"
  create_test_key "$test_key" "test_list_key"
  
  run main attach "$test_key"
  assert_success
  
  run main list
  assert_success
  assert_output --partial "test_list_key"
}

@test "list with -l flag works" {
  local test_key="$BATS_TMPDIR/test_l_flag_rsa"
  create_test_key "$test_key" "test_l_flag"
  
  run main attach "$test_key"
  assert_success
  
  run main -l
  assert_success
  assert_output --partial "test_l_flag"
}

@test "list with --list flag works" {
  local test_key="$BATS_TMPDIR/test_list_flag_rsa"
  create_test_key "$test_key" "test_list_flag"
  
  run main attach "$test_key"
  assert_success
  
  run main --list
  assert_success
  assert_output --partial "test_list_flag"
}

@test "keys command shows attached keys" {
  local test_key="$BATS_TMPDIR/test_keys_key_rsa"
  create_test_key "$test_key" "test_keys_key"
  
  run main attach "$test_key"
  assert_success
  
  run main keys
  assert_success
  assert_output --partial "test_keys_key"
}

@test "keys with -k flag works" {
  local test_key="$BATS_TMPDIR/test_k_flag_rsa"
  create_test_key "$test_key" "test_k_flag"
  
  run main attach "$test_key"
  assert_success
  
  run main -k
  assert_success
  assert_output --partial "test_k_flag"
}

@test "keys with --keys flag works" {
  local test_key="$BATS_TMPDIR/test_keys_flag_rsa"
  create_test_key "$test_key" "test_keys_flag"
  
  run main attach "$test_key"
  assert_success
  
  run main --keys
  assert_success
  assert_output --partial "test_keys_flag"
}

@test "timeout command should update timeouts" {
  local test_key="$BATS_TMPDIR/test_timeout_key_rsa"
  create_test_key "$test_key"
  
  run main attach "$test_key"
  assert_success
  
  run main timeout 1800
  assert_success
  assert_output --partial "Updated 1 keys."
}

@test "timeout with -t flag works" {
  local test_key="$BATS_TMPDIR/test_t_flag_key_rsa"
  create_test_key "$test_key"
  
  run main attach "$test_key"
  assert_success
  
  run main -t 1800
  assert_success
  assert_output --partial "Updated 1 keys."
}

@test "timeout with --timeout flag works" {
  local test_key="$BATS_TMPDIR/test_timeout_flag_key_rsa"
  create_test_key "$test_key"
  
  run main attach "$test_key"
  assert_success
  
  run main --timeout 1800
  assert_success
  assert_output --partial "Updated 1 keys."
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
  local test_key1="$BATS_TMPDIR/timeout_key1_rsa"
  local test_key2="$BATS_TMPDIR/timeout_key2_rsa"
  create_test_key "$test_key1" "key1"
  create_test_key "$test_key2" "key2"
  
  run main attach "$test_key1"
  assert_success
  run main attach "$test_key2"
  assert_success
  
  # Remove one key file
  rm -f "$test_key2"
  
  run main timeout 1800
  assert_success
  # Should report 1 key updated (key1)
  assert_output --partial "Updated 1 keys"
}

@test "timeout handles boundary values correctly" {
  local test_key="$BATS_TMPDIR/boundary_key_rsa"
  create_test_key "$test_key" "boundary_test"
  
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
