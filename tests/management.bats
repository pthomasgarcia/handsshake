#!/usr/bin/env bats

load "test_helper/bats-support/load.bash"
load "test_helper/bats-assert/load.bash"
load "test_helper/common_setup.bash"

# --- Flush Operations ---

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
  echo "$BATS_TMPDIR/identities/nonexistent.identity" >> "$STATE_DIR/added_keys.list"
  
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

# --- List Operations ---

@test "list command shows attached keys" {
  local test_key
  test_key=$(generate_test_identity "list-basic" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  run main list
  assert_success
  assert_output --partial "handsshake-test-list-basic"
}

@test "list with -l flag works" {
  local test_key
  test_key=$(generate_test_identity "list-l" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  run main -l
  assert_success
  assert_output --partial "handsshake-test-list-l"
}

@test "list with --list flag works" {
  local test_key
  test_key=$(generate_test_identity "list-flag" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  run main --list
  assert_success
  assert_output --partial "handsshake-test-list-flag"
}

@test "list command shows consistent output format" {
  local test_key
  test_key=$(generate_test_identity "list-format" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  run main list
  assert_success
  
  # Account for the "Attached keys:" header
  # Should show: key-size SHA256:fingerprint comment (RSA)
  assert_output --regexp "Attached keys:[[:space:]]+[0-9]+ SHA256:[A-Za-z0-9+/]+.*handsshake-test-list-format.*\(RSA\)$"
}

@test "list provides helpful message when agent is unreachable" {
  # Kill agent without cleanup
  if [[ -f "$STATE_DIR/ssh-agent.env" ]]; then
    source "$STATE_DIR/ssh-agent.env"
    kill "$SSH_AGENT_PID" 2>/dev/null || true
  fi
  
  # Try to list - ensure_agent should detect dead agent and restart
  run main list
  assert_success
  assert_output --partial "Agent is empty"
}

# --- Key Display Operations ---

@test "keys command shows attached keys" {
  local test_key
  test_key=$(generate_test_identity "keys-basic" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  run main keys
  assert_success
  assert_output --partial "handsshake-test-keys-basic"
}

@test "keys command outputs valid SSH public key format" {
  local test_key
  test_key=$(generate_test_identity "keys-format" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  run main keys
  assert_success
  
  # Verify it's a valid SSH public key format
  assert_output --regexp "^ssh-[a-z0-9-]+ [A-Za-z0-9+/=]+ handsshake-test-keys-format$"
}

@test "keys with -k flag works" {
  local test_key
  test_key=$(generate_test_identity "keys-k" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  run main -k
  assert_success
  assert_output --partial "handsshake-test-keys-k"
}

@test "keys with --keys flag works" {
  local test_key
  test_key=$(generate_test_identity "keys-flag" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  run main --keys
  assert_success
  assert_output --partial "handsshake-test-keys-flag"
}

# --- Timeout Operations ---

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
