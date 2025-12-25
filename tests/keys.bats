#!/usr/bin/env bats

load "test_helper"

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
  assert_output --regexp \
      "^ssh-[a-z0-9-]+ [A-Za-z0-9+/=]+ handsshake-test-keys-format$"
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
