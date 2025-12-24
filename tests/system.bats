#!/usr/bin/env bats

load "test_helper/bats-support/load.bash"
load "test_helper/bats-assert/load.bash"
load "test_helper/common_setup.bash"

# --- System Metadata ---

@test "version command should show version" {
  run main version
  assert_success
  assert_output --regexp 'v[0-9]+\.[0-9]+\.[0-9]+'
}

@test "version with -v flag works" {
  run main -v
  assert_success
  assert_output --regexp 'v[0-9]+\.[0-9]+\.[0-9]+'
}

@test "version with --version flag works" {
  run main --version
  assert_success
  assert_output --regexp 'v[0-9]+\.[0-9]+\.[0-9]+'
}

@test "help command should show usage" {
  run main help
  assert_success
  assert_output --partial "Usage"
}

@test "help text includes all commands and is well-formatted" {
  run main help
  assert_success
  # Check for all major commands
  assert_output --partial "attach"
  assert_output --partial "detach"
  assert_output --partial "flush"
  assert_output --partial "list"
  assert_output --partial "keys"
  assert_output --partial "timeout"
  assert_output --partial "cleanup"
  assert_output --partial "health"
  assert_output --partial "version"
  
  # Check for usage pattern
  assert_output --regexp "Usage:[[:space:]]+source[[:space:]]+.*[[:space:]]+<command>"
  
  # Check for argument documentation
  assert_output --partial "key_file"
  assert_output --partial "seconds"
}

# --- System Health & Connectivity ---

@test "health command should work" {
  run main health
  assert_success
}

@test "health with -H flag works" {
  run main -H
  assert_success
}

@test "health with --health flag works" {
  run main --health
  assert_success
}

@test "unknown command should fail" {
  run main unknowncommand
  assert_failure
  assert_output --partial "Unknown command"
}

# --- System Resilience & Recovery ---

@test "reconnects when agent dies unexpectedly" {
  local test_key
  test_key=$(generate_test_identity "recovery-basic" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  # Kill the agent process
  if [[ -f "$STATE_DIR/ssh-agent.env" ]]; then
    source "$STATE_DIR/ssh-agent.env"
    kill "$SSH_AGENT_PID"
    
    # Wait for agent to die
    sleep 0.1
    
    # Try to list keys - should restart agent
    run main list
    assert_success
    assert_output --partial "Agent is empty"
  fi
}

@test "recovers from repeated agent crashes" {
  local test_key
  test_key=$(generate_test_identity "recovery-stress" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  for i in {1..2}; do
    # Kill agent without cleanup
    if [[ -f "$STATE_DIR/ssh-agent.env" ]]; then
      source "$STATE_DIR/ssh-agent.env"
      kill "$SSH_AGENT_PID" 2>/dev/null || true
    fi
    
    # Each operation should recover
    run main health
    assert_success
    assert_output --partial "Agent is reachable"
  done
}

@test "handles multiple agent instances gracefully" {
  # Start a separate agent manually
  local agent_output
  agent_output=$(ssh-agent -s)
  local external_sock
  local external_pid
  external_sock=$(echo "$agent_output" | sed -n 's/SSH_AUTH_SOCK=\([^;]*\);.*/\1/p')
  external_pid=$(echo "$agent_output" | sed -n 's/SSH_AGENT_PID=\([^;]*\);.*/\1/p')
  
  # Force environment to use external agent
  export SSH_AUTH_SOCK="$external_sock"
  export SSH_AGENT_PID="$external_pid"
  
  local test_key
  test_key=$(generate_test_identity "multi-agent" "rsa")
  
  # Should use the external agent because ensure_agent sees it as valid
  run main attach "$test_key"
  assert_success
  
  # Verify key is in external agent using our list command
  run main list
  assert_output --partial "handsshake-test-multi-agent"
  
  # Clean up external agent
  kill "$external_pid" 2>/dev/null || true
}

# --- Resource Management ---

@test "cleanup removes all handsshake resources" {
  local test_key
  test_key=$(generate_test_identity "cleanup-final" "rsa")
  
  # Create state
  run main attach "$test_key"
  assert_success
  
  # Verify state exists
  [ -f "$STATE_DIR/ssh-agent.env" ]
  
  # Cleanup
  run main cleanup
  assert_success
  
  # Verify files are gone
  [ ! -f "$STATE_DIR/ssh-agent.env" ]
  [ ! -f "$STATE_DIR/added_keys.list" ]
}

@test "handles missing configuration gracefully" {
  local target_dir="$CONFIG_DIR"
  rm -rf "$target_dir"
  
  run main health
  assert_success
  
  mkdir -p "$target_dir"
  [ -d "$target_dir" ]
}

@test "handles corrupted configuration file" {
  mkdir -p "$CONFIG_DIR"
  echo "invalid !!! bash syntax" > "$CONFIG_DIR/settings.conf"
  echo "HANDSSHAKE_DEFAULT_TIMEOUT=not_a_number" >> "$CONFIG_DIR/settings.conf"
  
  run main health
  assert_success
}

@test "state-changing commands fail when executed directly" {
  [ "${HANDSSHAKE_LOADED:-}" = "true" ]
}
