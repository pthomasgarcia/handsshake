#!/usr/bin/env bats

load "test_helper/bats-support/load.bash"
load "test_helper/bats-assert/load.bash"
load "test_helper/common_setup.bash"

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
