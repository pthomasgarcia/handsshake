#!/usr/bin/env bats

load "test_helper/bats-support/load.bash"
load "test_helper/bats-assert/load.bash"
load "test_helper/common_setup.bash"

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
