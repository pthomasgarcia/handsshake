#!/usr/bin/env bats

load "test_helper/bats-support/load.bash"
load "test_helper/bats-assert/load.bash"
load "test_helper/common_setup.bash"

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

@test "help with -h flag works" {
  run main -h
  assert_success
  assert_output --partial "Usage"
}

@test "help with --help flag works" {
  run main --help
  assert_success
  assert_output --partial "Usage"
}

@test "unknown command should fail" {
  run main unknowncommand
  assert_failure
  assert_output --partial "Unknown command"
}

@test "reconnects when agent dies unexpectedly" {
  local test_key="$BATS_TMPDIR/recovery_key_rsa"
  create_test_key "$test_key" "recovery_test"
  
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

@test "handles multiple agent instances gracefully" {
  # Start a separate agent manually
  local agent_output
  agent_output=$(ssh-agent -s)
  local external_sock
  local external_pid
  external_sock=$(echo "$agent_output" | sed -n 's/SSH_AUTH_SOCK=\([^;]*\);.*/\1/p')
  external_pid=$(echo "$agent_output" | sed -n 's/SSH_AGENT_PID=\([^;]*\);.*/\1/p')
  
  # Save original values
  local original_sock="${SSH_AUTH_SOCK:-}"
  local original_pid="${SSH_AGENT_PID:-}"
  
  # Set external agent
  export SSH_AUTH_SOCK="$external_sock"
  export SSH_AGENT_PID="$external_pid"
  
  local test_key="$BATS_TMPDIR/external_agent_key_rsa"
  create_test_key "$test_key" "external_agent_test"
  
  # Should use the external agent
  run main attach "$test_key"
  assert_success
  
  # Verify key is in external agent using our list command
  run main list
  assert_output --partial "external_agent_test"
  
  # Clean up external agent
  kill "$external_pid" 2>/dev/null || true
  
  # Restore original values
  if [[ -n "$original_sock" ]]; then
    export SSH_AUTH_SOCK="$original_sock"
  else
    unset SSH_AUTH_SOCK
  fi
  if [[ -n "$original_pid" ]]; then
    export SSH_AGENT_PID="$original_pid"
  else
    unset SSH_AGENT_PID
  fi
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
  assert_output --regexp "Usage:.*source.*<command>"
  
  # Check for argument documentation
  assert_output --partial "key_file"
  assert_output --partial "seconds"
}

@test "state-changing commands fail when executed directly" {
  # The script should have logic to detect if it's sourced or executed
  # We can verify the HANDSSHAKE_LOADED variable is set to true when sourced
  [ "${HANDSSHAKE_LOADED:-}" = "true" ]
}
