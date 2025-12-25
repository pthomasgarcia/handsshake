#!/usr/bin/env bats

load "test_helper"

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
  assert_output --regexp \
      "Attached keys:[[:space:]]+[0-9]+ SHA256:[A-Za-z0-9+/]+" \
      ".*handsshake-test-list-format.*\(RSA\)$"
}

@test "list provides helpful message when agent is unreachable" {
  # Kill agent without cleanup
  if [[ -f "$STATE_DIR/ssh-agent.env" ]]; then
    # shellcheck disable=SC1091
    source "$STATE_DIR/ssh-agent.env"
    kill "$SSH_AGENT_PID" 2>/dev/null || true
  fi
  
  # Try to list - ensure_agent should detect dead agent and restart
  run main list
  assert_success
  assert_output --partial "Agent is empty"
}
