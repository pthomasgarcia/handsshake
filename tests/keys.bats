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

@test "keys with -e flag works" {
  local test_key
  test_key=$(generate_test_identity "keys-e" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  run main -e
  assert_success
  assert_output --partial "handsshake-test-keys-e"
}

@test "keys with --export flag works" {
  local test_key
  test_key=$(generate_test_identity "keys-flag" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  run main --export
  assert_success
  assert_output --partial "handsshake-test-keys-flag"
}
