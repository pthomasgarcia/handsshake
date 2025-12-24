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
  
  # Configure handsshake to use a unique test name instead of id_ed25519
  export HANDSSHAKE_DEFAULT_KEY="$HOME/.ssh/handsshake_test_default_key"
  
  safe_cp "$test_key" "$HANDSSHAKE_DEFAULT_KEY"
  safe_cp "$test_key.pub" "${HANDSSHAKE_DEFAULT_KEY}.pub"
  
  run main attach
  
  assert_success
  assert_output --partial "Key '$HANDSSHAKE_DEFAULT_KEY' attached"
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

@test "attach verifies correct key size is detected" {
  local test_key="$BATS_TMPDIR/test_key_rsa_size"
  create_test_key "$test_key" "size_test"
  
  run main attach "$test_key"
  assert_success
  
  # Verify the key was added with correct size (RSA 2048)
  run ssh-add -l
  assert_output --partial "2048"
}

@test "attach preserves key comment in agent" {
  local test_key="$BATS_TMPDIR/comment_test_rsa"
  local comment="user@hostname-$(date +%s)"
  create_test_key "$test_key" "$comment"
  
  run main attach "$test_key"
  assert_success
  
  # Verify comment appears in agent listing
  verify_agent_contains_key "$comment"
}

@test "attach fails gracefully with corrupted key file" {
  local test_key="$BATS_TMPDIR/corrupted_key"
  echo "invalid key data" > "$test_key"
  echo "invalid public key" > "$test_key.pub"
  
  run main attach "$test_key"
  assert_failure
  assert_output --partial "not a valid SSH key"
  
  # Verify cleanup - no partial state
  verify_key_not_recorded "$test_key"
}

@test "attach prevents duplicate key additions" {
  local test_key="$BATS_TMPDIR/duplicate_test_rsa"
  create_test_key "$test_key" "duplicate_test"
  
  # First attach
  run main attach "$test_key"
  assert_success
  
  # Second attach (should be idempotent)
  run main attach "$test_key"
  assert_success
  assert_output --partial "already attached"
  
  # Verify only one instance in agent
  run ssh-add -l
  # Count lines containing the comment
  local count
  count=$(echo "$output" | grep -c "duplicate_test" || true)
  [ "$count" -eq 1 ]
}

@test "attach lifecycle: add, verify, detach, verify removal" {
  local test_key="$BATS_TMPDIR/lifecycle_key_rsa"
  create_test_key "$test_key" "lifecycle_test"
  
  # 1. Attach
  run main attach "$test_key"
  assert_success
  
  # 2. Verify in agent
  verify_agent_contains_key "lifecycle_test"
  
  # 3. Verify in records
  verify_key_recorded "$test_key"
  
  # 4. Detach
  run main detach "$test_key"
  assert_success
  
  # 5. Verify removal from agent (agent might be empty or have other keys)
  run ssh-add -l
  refute_output --partial "lifecycle_test"
  
  # 6. Verify removal from records
  verify_key_not_recorded "$test_key"
}
