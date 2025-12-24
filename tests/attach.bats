#!/usr/bin/env bats

load "test_helper/bats-support/load.bash"
load "test_helper/bats-assert/load.bash"
load "test_helper/common_setup.bash"

@test "attach command should add a key" {
  local test_key="$BATS_TMPDIR/test_key_rsa"
  create_test_key "$test_key" "test_key_comment"
  
  run main attach "$test_key"
  
  assert_success
  assert_output --partial "Key '$test_key' attached"
  
  verify_key_recorded "$test_key"
  verify_agent_contains_key "test_key_comment"
}

@test "attach with -a flag works" {
  local test_key="$BATS_TMPDIR/test_a_flag_rsa"
  create_test_key "$test_key" "test_a_flag"
  
  run main -a "$test_key"
  
  assert_success
  assert_output --partial "Key '$test_key' attached"
  
  verify_key_recorded "$test_key"
  verify_agent_contains_key "test_a_flag"
}

@test "attach with --attach flag works" {
  local test_key="$BATS_TMPDIR/test_attach_flag_rsa"
  create_test_key "$test_key" "test_attach_flag"
  
  run main --attach "$test_key"
  
  assert_success
  assert_output --partial "Key '$test_key' attached"
  
  verify_key_recorded "$test_key"
  verify_agent_contains_key "test_attach_flag"
}

@test "attach with non-existent key should fail" {
  local invalid_key="$BATS_TMPDIR/nonexistent_key"
  
  run main attach "$invalid_key"
  
  assert_failure
  assert_output --partial "Invalid key file"
}

@test "attach without argument uses default key" {
  local test_key="$BATS_TMPDIR/test_default_key_ed25519"
  create_test_key "$test_key" "default_key_test"
  
  cp "$test_key" "$HOME/.ssh/id_ed25519"
  cp "$test_key.pub" "$HOME/.ssh/id_ed25519.pub"
  
  run main attach
  
  assert_success
  assert_output --partial "Key '$HOME/.ssh/id_ed25519' attached"
}

@test "attach Ed25519 key specifically" {
  local test_key="$BATS_TMPDIR/test_key_ed25519"
  create_test_key "$test_key" "ed25519_test"
  
  run main attach "$test_key"
  
  assert_success
  assert_output --partial "Key '$test_key' attached"
}

@test "attach ECDSA key specifically" {
  local test_key="$BATS_TMPDIR/test_key_ecdsa"
  create_test_key "$test_key" "ecdsa_test"
  
  run main attach "$test_key"
  
  assert_success
  assert_output --partial "Key '$test_key' attached"
}
