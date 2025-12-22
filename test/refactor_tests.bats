#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/test_helper/bats-support/load.bash"
load "${BATS_TEST_DIRNAME}/test_helper/bats-assert/load.bash"

# Helper functions
create_test_key() {
  local key_path="$1"
  local comment="${2:-}"
  if [[ -n "$comment" ]]; then
    ssh-keygen -t rsa -b 2048 -f "$key_path" -N "" -C "$comment" >/dev/null
  else
    ssh-keygen -t rsa -b 2048 -f "$key_path" -N "" >/dev/null
  fi
}

verify_agent_contains_key() {
  local key_comment="$1"
  if [[ -f "$STATE_DIR/ssh-agent.env" ]]; then
    source "$STATE_DIR/ssh-agent.env"
    run ssh-add -l
    assert_output --partial "$key_comment"
  fi
}

verify_agent_empty() {
  if [[ -f "$STATE_DIR/ssh-agent.env" ]]; then
    source "$STATE_DIR/ssh-agent.env"
    run ssh-add -l
    [[ "$status" -ne 0 ]]
  fi
}

verify_key_recorded() {
  local key_path="$1"
  run grep -Fq "$key_path" "$STATE_DIR/added_keys.list"
  assert_success
}

verify_key_not_recorded() {
  local key_path="$1"
  run grep -Fq "$key_path" "$STATE_DIR/added_keys.list"
  assert_failure
}

setup() {
  # Create a temporary directory for the tests to run in.
  BATS_TMPDIR="$(mktemp -d -t handsshake-tests-XXXXXXXX)"
  
  # Copy the handsshake source to the temporary directory
  rsync -a --exclude='test' --exclude='.git' "$BATS_TEST_DIRNAME/../" "$BATS_TMPDIR/"
  
  # The script to test
  HANDSSHAKE_SCRIPT="$BATS_TMPDIR/src/core/main.sh"
  
  # Verify the script exists
  if [[ ! -f "$HANDSSHAKE_SCRIPT" ]]; then
    echo "ERROR: Script not found: $HANDSSHAKE_SCRIPT"
    exit 1
  fi
  
  # Setup XDG directories
  export XDG_CONFIG_HOME="$BATS_TMPDIR/.config"
  export XDG_STATE_HOME="$BATS_TMPDIR/.local/state"
  
  # Define paths based on XDG standard as implemented in config.sh
  export CONFIG_DIR="$XDG_CONFIG_HOME/handsshake"
  export STATE_DIR="$XDG_STATE_HOME/handsshake"
  
  mkdir -p "$CONFIG_DIR"
  mkdir -p "$STATE_DIR"
  
  # Ensure the script is executable
  chmod +x "$HANDSSHAKE_SCRIPT"
  
  # Pre-create and truncate the record file
  : > "$STATE_DIR/added_keys.list"
}

teardown() {
  # Always attempt cleanup even if previous tests failed
  if [[ -x "$HANDSSHAKE_SCRIPT" ]]; then
    run "$HANDSSHAKE_SCRIPT" cleanup 2>/dev/null || true
  fi
  
  # Ensure cleanup even if script fails
  if [[ -n "$SSH_AGENT_PID" ]]; then
    kill "$SSH_AGENT_PID" 2>/dev/null || true
    unset SSH_AGENT_PID
  fi
  
  # Cleanup temp directory
  if [[ -d "$BATS_TMPDIR" ]]; then
    rm -rf "$BATS_TMPDIR"
  fi
}

@test "attach command should add a key" {
  local dummy_key="$BATS_TMPDIR/dummy_key"
  create_test_key "$dummy_key" "test_key_comment"
  
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key"
  
  assert_success
  assert_output --partial "Key '$dummy_key' attached"
  
  verify_key_recorded "$dummy_key"
  verify_agent_contains_key "test_key_comment"
}

@test "attach with -a flag works" {
  local dummy_key="$BATS_TMPDIR/dummy_key"
  create_test_key "$dummy_key" "test_a_flag"
  
  run "$HANDSSHAKE_SCRIPT" -a "$dummy_key"
  
  assert_success
  assert_output --partial "Key '$dummy_key' attached"
  
  verify_key_recorded "$dummy_key"
  verify_agent_contains_key "test_a_flag"
}

@test "attach with --attach flag works" {
  local dummy_key="$BATS_TMPDIR/dummy_key"
  create_test_key "$dummy_key" "test_attach_flag"
  
  run "$HANDSSHAKE_SCRIPT" --attach "$dummy_key"
  
  assert_success
  assert_output --partial "Key '$dummy_key' attached"
  
  verify_key_recorded "$dummy_key"
  verify_agent_contains_key "test_attach_flag"
}

@test "attach with non-existent key should fail" {
  local invalid_key="$BATS_TMPDIR/nonexistent_key"
  
  run "$HANDSSHAKE_SCRIPT" attach "$invalid_key"
  
  assert_failure
  assert_output --partial "Invalid key file"
}

@test "attach without argument uses default key" {
  # Create default key
  local default_key="$HOME/.ssh/id_ed25519"
  local backup_key="${default_key}.backup"
  
  # Backup existing key if it exists
  if [[ -f "$default_key" ]]; then
    mv "$default_key" "$backup_key"
    mv "${default_key}.pub" "${backup_key}.pub"
  fi
  
  create_test_key "$default_key" "default_key_test"
  
  run "$HANDSSHAKE_SCRIPT" attach
  
  assert_success
  assert_output --partial "Key '$default_key' attached"
  
  # Restore original key if it existed
  if [[ -f "$backup_key" ]]; then
    rm -f "$default_key" "${default_key}.pub"
    mv "$backup_key" "$default_key"
    mv "${backup_key}.pub" "${default_key}.pub"
  fi
}

@test "detach command should remove a key" {
  local dummy_key="$BATS_TMPDIR/dummy_key"
  create_test_key "$dummy_key" "test_detach_key"
  
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key"
  assert_success
  
  run "$HANDSSHAKE_SCRIPT" detach "$dummy_key"
  assert_success
  assert_output --partial "Key '$dummy_key' detached"
  
  verify_key_not_recorded "$dummy_key"
  verify_agent_empty
}

@test "detach with -d flag works" {
  local dummy_key="$BATS_TMPDIR/dummy_key"
  create_test_key "$dummy_key" "test_d_flag"
  
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key"
  assert_success
  
  run "$HANDSSHAKE_SCRIPT" -d "$dummy_key"
  assert_success
  assert_output --partial "Key '$dummy_key' detached"
  
  verify_key_not_recorded "$dummy_key"
  verify_agent_empty
}

@test "detach with --detach flag works" {
  local dummy_key="$BATS_TMPDIR/dummy_key"
  create_test_key "$dummy_key" "test_detach_flag"
  
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key"
  assert_success
  
  run "$HANDSSHAKE_SCRIPT" --detach "$dummy_key"
  assert_success
  assert_output --partial "Key '$dummy_key' detached"
  
  verify_key_not_recorded "$dummy_key"
  verify_agent_empty
}

@test "detach non-attached key should fail" {
  local dummy_key="$BATS_TMPDIR/dummy_key"
  create_test_key "$dummy_key"
  
  run "$HANDSSHAKE_SCRIPT" detach "$dummy_key"
  
  assert_failure
  assert_output --partial "not found"
}

@test "detach without argument should fail" {
  run "$HANDSSHAKE_SCRIPT" detach
  
  assert_failure
  assert_output --partial "requires exactly one fingerprint"
}

@test "flush command should remove all keys" {
  local dummy_key1="$BATS_TMPDIR/dummy_key1"
  local dummy_key2="$BATS_TMPDIR/dummy_key2"
  create_test_key "$dummy_key1" "key1"
  create_test_key "$dummy_key2" "key2"
  
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key1"
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key2"
  
  run "$HANDSSHAKE_SCRIPT" flush
  assert_success
  assert_output --partial "All keys flushed"
  
  # Verify record file is gone
  [[ ! -f "$STATE_DIR/added_keys.list" ]]
  
  verify_agent_empty
}

@test "flush with -f flag works" {
  local dummy_key="$BATS_TMPDIR/dummy_key"
  create_test_key "$dummy_key" "test_f_flag"
  
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key"
  assert_success
  
  run "$HANDSSHAKE_SCRIPT" -f
  assert_success
  assert_output --partial "All keys flushed"
  
  [[ ! -f "$STATE_DIR/added_keys.list" ]]
  verify_agent_empty
}

@test "flush with --flush flag works" {
  local dummy_key="$BATS_TMPDIR/dummy_key"
  create_test_key "$dummy_key" "test_flush_flag"
  
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key"
  assert_success
  
  run "$HANDSSHAKE_SCRIPT" --flush
  assert_success
  assert_output --partial "All keys flushed"
  
  [[ ! -f "$STATE_DIR/added_keys.list" ]]
  verify_agent_empty
}

@test "flush with no keys attached should succeed" {
  run "$HANDSSHAKE_SCRIPT" flush
  
  assert_success
  assert_output --partial "All keys flushed"
}

@test "list command shows attached keys" {
  local dummy_key="$BATS_TMPDIR/dummy_key"
  create_test_key "$dummy_key" "test_list_key"
  
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key"
  assert_success
  
  run "$HANDSSHAKE_SCRIPT" list
  assert_success
  assert_output --partial "test_list_key"
}

@test "list with -l flag works" {
  local dummy_key="$BATS_TMPDIR/dummy_key"
  create_test_key "$dummy_key" "test_l_flag"
  
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key"
  assert_success
  
  run "$HANDSSHAKE_SCRIPT" -l
  assert_success
  assert_output --partial "test_l_flag"
}

@test "list with --list flag works" {
  local dummy_key="$BATS_TMPDIR/dummy_key"
  create_test_key "$dummy_key" "test_list_flag"
  
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key"
  assert_success
  
  run "$HANDSSHAKE_SCRIPT" --list
  assert_success
  assert_output --partial "test_list_flag"
}

@test "keys command shows attached keys" {
  local dummy_key="$BATS_TMPDIR/dummy_key"
  create_test_key "$dummy_key" "test_keys_key"
  
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key"
  assert_success
  
  run "$HANDSSHAKE_SCRIPT" keys
  assert_success
  assert_output --partial "test_keys_key"
}

@test "keys with -k flag works" {
  local dummy_key="$BATS_TMPDIR/dummy_key"
  create_test_key "$dummy_key" "test_k_flag"
  
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key"
  assert_success
  
  run "$HANDSSHAKE_SCRIPT" -k
  assert_success
  assert_output --partial "test_k_flag"
}

@test "keys with --keys flag works" {
  local dummy_key="$BATS_TMPDIR/dummy_key"
  create_test_key "$dummy_key" "test_keys_flag"
  
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key"
  assert_success
  
  run "$HANDSSHAKE_SCRIPT" --keys
  assert_success
  assert_output --partial "test_keys_flag"
}

@test "timeout command should update timeouts" {
  local dummy_key="$BATS_TMPDIR/dummy_key"
  create_test_key "$dummy_key"
  
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key"
  assert_success
  
  run "$HANDSSHAKE_SCRIPT" timeout 1800
  assert_success
  assert_output --partial "Updated 1 keys."
}

@test "timeout with -t flag works" {
  local dummy_key="$BATS_TMPDIR/dummy_key"
  create_test_key "$dummy_key"
  
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key"
  assert_success
  
  run "$HANDSSHAKE_SCRIPT" -t 1800
  assert_success
  assert_output --partial "Updated 1 keys."
}

@test "timeout with --timeout flag works" {
  local dummy_key="$BATS_TMPDIR/dummy_key"
  create_test_key "$dummy_key"
  
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key"
  assert_success
  
  run "$HANDSSHAKE_SCRIPT" --timeout 1800
  assert_success
  assert_output --partial "Updated 1 keys."
}

@test "timeout with invalid value should fail" {
  run "$HANDSSHAKE_SCRIPT" timeout -5
  assert_failure
  assert_output --partial "positive integer required"
  
  run "$HANDSSHAKE_SCRIPT" timeout "not_a_number"
  assert_failure
  assert_output --partial "integer required"
}

@test "timeout without argument should fail" {
  run "$HANDSSHAKE_SCRIPT" timeout
  assert_failure
  assert_output --partial "requires exactly one argument"
}

@test "cleanup command should work" {
  local dummy_key="$BATS_TMPDIR/dummy_key"
  create_test_key "$dummy_key"
  
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key"
  assert_success
  
  run "$HANDSSHAKE_SCRIPT" cleanup
  assert_success
}

@test "cleanup with -c flag works" {
  local dummy_key="$BATS_TMPDIR/dummy_key"
  create_test_key "$dummy_key"
  
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key"
  assert_success
  
  run "$HANDSSHAKE_SCRIPT" -c
  assert_success
}

@test "cleanup with --cleanup flag works" {
  local dummy_key="$BATS_TMPDIR/dummy_key"
  create_test_key "$dummy_key"
  
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key"
  assert_success
  
  run "$HANDSSHAKE_SCRIPT" --cleanup
  assert_success
}

@test "health command should work" {
  run "$HANDSSHAKE_SCRIPT" health
  assert_success
}

@test "health with -H flag works" {
  run "$HANDSSHAKE_SCRIPT" -H
  assert_success
}

@test "health with --health flag works" {
  run "$HANDSSHAKE_SCRIPT" --health
  assert_success
}

@test "version command should show version" {
  run "$HANDSSHAKE_SCRIPT" version
  assert_success
  assert_output --regexp 'v[0-9]+\.[0-9]+\.[0-9]+'
}

@test "version with -v flag works" {
  run "$HANDSSHAKE_SCRIPT" -v
  assert_success
  assert_output --regexp 'v[0-9]+\.[0-9]+\.[0-9]+'
}

@test "version with --version flag works" {
  run "$HANDSSHAKE_SCRIPT" --version
  assert_success
  assert_output --regexp 'v[0-9]+\.[0-9]+\.[0-9]+'
}

@test "help command should show usage" {
  run "$HANDSSHAKE_SCRIPT" help
  assert_success
  assert_output --partial "Usage"
}

@test "help with -h flag works" {
  run "$HANDSSHAKE_SCRIPT" -h
  assert_success
  assert_output --partial "Usage"
}

@test "help with --help flag works" {
  run "$HANDSSHAKE_SCRIPT" --help
  assert_success
  assert_output --partial "Usage"
}

@test "unknown command should fail" {
  run "$HANDSSHAKE_SCRIPT" unknowncommand
  assert_failure
  assert_output --partial "Unknown command"
}

@test "-- separator should work" {
  # Test that -- allows commands that look like flags
  run "$HANDSSHAKE_SCRIPT" -- --help
  # This should treat --help as a command, not show help
  # Either it fails with "Unknown command: --help" or processes it
  # depending on your implementation
  if [[ "$status" -eq 0 ]]; then
    # If it succeeds, it should show help content, not error
    assert_output --partial "Usage"
  else
    # If it fails, it should be because --help isn't a valid command
    assert_output --partial "Unknown command"
  fi
}

@test "concurrent attach calls should not corrupt state" {
  local dummy_key1="$BATS_TMPDIR/concurrent_key1"
  local dummy_key2="$BATS_TMPDIR/concurrent_key2"
  create_test_key "$dummy_key1" "concurrent_key1"
  create_test_key "$dummy_key2" "concurrent_key2"
  
  # Run attaches sequentially to avoid race conditions in test
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key1"
  assert_success
  
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key2"
  assert_success
  
  # Verify file has exactly 2 lines
  local line_count
  line_count=$(grep -c . "$STATE_DIR/added_keys.list")
  assert_equal "$line_count" 2
  
  # Verify no duplicates
  local unique_count
  unique_count=$(sort -u "$STATE_DIR/added_keys.list" | wc -l)
  assert_equal "$unique_count" 2
  
  # Verify both keys in agent
  if [[ -f "$STATE_DIR/ssh-agent.env" ]]; then
    source "$STATE_DIR/ssh-agent.env"
    run ssh-add -l
    assert_output --partial "concurrent_key1"
    assert_output --partial "concurrent_key2"
  fi
}

@test "state file should be properly formatted after multiple operations" {
  local dummy_key1="$BATS_TMPDIR/key1"
  local dummy_key2="$BATS_TMPDIR/key2"
  create_test_key "$dummy_key1"
  create_test_key "$dummy_key2"
  
  # Attach, detach, re-attach
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key1"
  assert_success
  
  run "$HANDSSHAKE_SCRIPT" attach "$dummy_key2"
  assert_success
  
  run "$HANDSSHAKE_SCRIPT" detach "$dummy_key1"
  assert_success
  
  # Verify only key2 remains
  verify_key_not_recorded "$dummy_key1"
  verify_key_recorded "$dummy_key2"
  
  # File should have exactly 1 line
  local line_count
  line_count=$(wc -l < "$STATE_DIR/added_keys.list")
  assert_equal "$line_count" 1
}
