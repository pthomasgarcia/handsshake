#!/usr/bin/env bats

load "test_helper"

@test "attach command should add a key" {
  local test_key
  test_key=$(generate_test_identity "basic-attach" "rsa")
  
  run main attach "$test_key"
  
  assert_success
  assert_output --partial "Key '$test_key' attached"
  
  verify_key_recorded "$test_key"
  verify_agent_contains_key "handsshake-test-basic-attach"
}

@test "attach with -a flag works" {
  local test_key
  test_key=$(generate_test_identity "flag-a" "rsa")
  
  run main -a "$test_key"
  
  assert_success
  assert_output --partial "Key '$test_key' attached"
  
  verify_key_recorded "$test_key"
  verify_agent_contains_key "handsshake-test-flag-a"
}

@test "attach with --attach flag works" {
  local test_key
  test_key=$(generate_test_identity "flag-attach" "rsa")
  
  run main --attach "$test_key"
  
  assert_success
  assert_output --partial "Key '$test_key' attached"
  
  verify_key_recorded "$test_key"
  verify_agent_contains_key "handsshake-test-flag-attach"
}

@test "attach with non-existent key should fail" {
  local invalid_key="$BATS_TMPDIR/identities/nonexistent.identity"
  
  run main attach "$invalid_key"
  
  assert_failure
  assert_output --partial "Invalid key file"
}

@test "attach without argument uses default key" {
  local test_key
  test_key=$(generate_test_identity "default-trap" "ed25519")
  
  # Configure handsshake to use a unique test name instead of id_ed25519
  export HANDSSHAKE_DEFAULT_KEY="$HOME/.ssh/hsh-test-default.identity"
  
  safe_cp "$test_key" "$HANDSSHAKE_DEFAULT_KEY"
  safe_cp "$test_key.pub" "${HANDSSHAKE_DEFAULT_KEY}.pub"
  
  run main attach
  
  assert_success
  assert_output --partial "Key '$HANDSSHAKE_DEFAULT_KEY' attached"
}

@test "attach Ed25519 key specifically" {
  local test_key
  test_key=$(generate_test_identity "specific-ed25519" "ed25519")
  
  run main attach "$test_key"
  
  assert_success
  assert_output --partial "Key '$test_key' attached"
}

@test "attach ECDSA key specifically" {
  local test_key
  test_key=$(generate_test_identity "specific-ecdsa" "ecdsa")
  
  run main attach "$test_key"
  
  assert_success
  assert_output --partial "Key '$test_key' attached"
}

@test "attach verifies correct key size is detected" {
  local test_key
  test_key=$(generate_test_identity "size-verify" "rsa")
  
  run main attach "$test_key"
  assert_success
  
  # Verify the key was added with correct size (RSA 2048)
  run ssh-add -l
  assert_output --partial "2048"
}

@test "attach preserves key comment in agent" {
  local comment
  comment="user@test-$(date +%s)"
  local identities_dir="$BATS_TMPDIR/identities"
  mkdir -p "$identities_dir"
  local test_key="$identities_dir/hsh-test-comment.identity"
  
  create_test_key "$test_key" "$comment"
  
  run main attach "$test_key"
  assert_success
  
  # Verify comment appears in agent listing
  verify_agent_contains_key "$comment"
}

@test "attach fails gracefully with corrupted key file" {
  local test_key="$BATS_TMPDIR/identities/corrupted.identity"
  mkdir -p "$(dirname "$test_key")"
  echo "invalid key data" > "$test_key"
  echo "invalid public key" > "$test_key.pub"
  
  run main attach "$test_key"
  assert_failure
  assert_output --partial "not a valid SSH key"
  
  # Verify cleanup - no partial state
  verify_key_not_recorded "$test_key"
}

@test "attach prevents duplicate key additions" {
  local test_key
  test_key=$(generate_test_identity "duplicate-check" "rsa")
  
  # First attach
  run main attach "$test_key"
  assert_success
  
  # Second attach (should be idempotent)
  run main attach "$test_key"
  assert_success
  assert_output --partial "already attached"
  
  # Verify only one instance in agent
  run ssh-add -l
  local count
  count=$(echo "$output" | grep -c "handsshake-test-duplicate-check" || true)
  [ "$count" -eq 1 ]
}

@test "attach lifecycle: add, verify, detach, verify removal" {
  local test_key
  test_key=$(generate_test_identity "lifecycle" "rsa")
  
  # 1. Attach
  run main attach "$test_key"
  assert_success
  
  # 2. Verify in agent
  verify_agent_contains_key "handsshake-test-lifecycle"
  
  # 3. Verify in records
  verify_key_recorded "$test_key"
  
  # 4. Detach
  run main detach "$test_key"
  assert_success
  
  # 5. Verify removal from agent
  run ssh-add -l
  refute_output --partial "handsshake-test-lifecycle"
  
  # 6. Verify removal from records
  verify_key_not_recorded "$test_key"
}

@test "attach with extra arguments should fail gracefully" {
  local test_key
  test_key=$(generate_test_identity "extra-args" "rsa")
  
  run main attach "$test_key" "extra_argument"
  [[ "$status" -ne 127 ]]
}
