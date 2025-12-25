#!/usr/bin/env bats

load "test_helper"

@test "flush command should remove all keys" {
  local key1
  local key2
  key1=$(generate_test_identity "flush-1" "rsa")
  key2=$(generate_test_identity "flush-2" "rsa")
  
  run main attach "$key1"
  run main attach "$key2"
  
  run main flush
  assert_success
  assert_output --partial "All keys flushed"
  
  [[ ! -f "$STATE_DIR/added_keys.list" ]]
  verify_agent_empty
}

@test "flush with -f flag works" {
  local test_key
  test_key=$(generate_test_identity "flush-f" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  run main -f
  assert_success
  assert_output --partial "All keys flushed"
  
  [[ ! -f "$STATE_DIR/added_keys.list" ]]
  verify_agent_empty
}

@test "flush with --flush flag works" {
  local test_key
  test_key=$(generate_test_identity "flush-flag" "rsa")
  
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
  mkdir -p "$(dirname "$STATE_DIR/added_keys.list")"
  echo "not a valid path" > "$STATE_DIR/added_keys.list"
  echo "/nonexistent/file" >> "$STATE_DIR/added_keys.list"
  echo "$BATS_TMPDIR/identities/nonexistent.identity" >> \
      "$STATE_DIR/added_keys.list"
  
  run main flush
  assert_success
  assert_output --partial "All keys flushed"
  
  # Record file should be removed
  [[ ! -f "$STATE_DIR/added_keys.list" ]]
}

@test "flush handles sequential operations gracefully" {
  local key1
  local key2
  key1=$(generate_test_identity "flush-seq-1" "rsa")
  key2=$(generate_test_identity "flush-seq-2" "rsa")
  
  run main attach "$key1"
  run main attach "$key2"
  
  # Rapid flush simulation
  run main flush
  assert_success
  
  # Second flush should be a safe no-op
  run main flush
  assert_success
  
  verify_agent_empty
  [ ! -f "$STATE_DIR/added_keys.list" ]
}
