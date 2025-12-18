#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/test_helper/bats-support/load.bash"
load "${BATS_TEST_DIRNAME}/test_helper/bats-assert/load.bash"

setup() {
  # Create a temporary directory for the tests to run in.
  BATS_TMPDIR="$(mktemp -d -t bats-XXXXXXXX)"
  
  # Copy the handsshake source to the temporary directory
  rsync -a --exclude='test' --exclude='.git' "$BATS_TEST_DIRNAME/../" "$BATS_TMPDIR/"
  
  # The script to test
  HANDSSHAKE_SCRIPT="$BATS_TMPDIR/src/core/main.sh"
  
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
  
  # Pre-create and truncate the record file to avoid race conditions and ensure clean state
  # Note: The application should create this if missing, but for tests we might want explicit state.
  # Using the XDG path now.
  : > "$STATE_DIR/added_keys.list"
}

teardown() {
  # Clean up the temporary directory
  rm -rf "$BATS_TMPDIR"
  
  # Kill any agent started during tests (if using a mock or real one)
  # Since we use real agents, we should try to kill them if we can identify them,
  # but main cleanup logic is hard to trigger here without calling the script.
  # pkill -u "$USER" ssh-agent # This is DANGEROUS in shared envs.
  # Instead rely on the script's strict containment or cleanup.
}

@test "refactor: add command should add a key" {
  # Create a real, temporary SSH key for testing with a specific comment
  local dummy_key="$BATS_TMPDIR/dummy_key"
  ssh-keygen -t rsa -b 2048 -f "$dummy_key" -N "" -C "test_key_comment" >/dev/null

  # Run the add command
  run "$HANDSSHAKE_SCRIPT" add "$dummy_key"
  
  # Check the output
  assert_success
  assert_output --partial "Key '$dummy_key' added"
  
  # Verify the key was recorded in the XDG state file
  run grep -Fq "$dummy_key" "$STATE_DIR/added_keys.list"
  assert_success
  
  # Verify the agent has the key by checking for the comment
  if [ -f "$STATE_DIR/ssh-agent.env" ]; then
      source "$STATE_DIR/ssh-agent.env"
      run ssh-add -l
      assert_output --partial "test_key_comment"
  fi
}

@test "refactor: remove command should remove a key" {
  # Add a key first
  local dummy_key="$BATS_TMPDIR/dummy_key"
  ssh-keygen -t rsa -b 2048 -f "$dummy_key" -N "" >/dev/null
  run "$HANDSSHAKE_SCRIPT" add "$dummy_key"
  assert_success

  # Now remove the key
  run "$HANDSSHAKE_SCRIPT" remove "$dummy_key"
  assert_success
  assert_output --partial "Key '$dummy_key' removed"
  
  # Verify the key is no longer in the record file
  run grep -Fq "$dummy_key" "$STATE_DIR/added_keys.list"
  assert_failure

  # Verify the agent no longer has the key
  if [ -f "$STATE_DIR/ssh-agent.env" ]; then
      source "$STATE_DIR/ssh-agent.env"
      run ssh-add -l
      assert_output --partial "The agent has no identities."
  fi
}

@test "refactor: remove-all command should remove all keys" {
  # Add a couple of keys
  local dummy_key1="$BATS_TMPDIR/dummy_key1"
  local dummy_key2="$BATS_TMPDIR/dummy_key2"
  ssh-keygen -t rsa -b 2048 -f "$dummy_key1" -N "" >/dev/null
  ssh-keygen -t rsa -b 2048 -f "$dummy_key2" -N "" >/dev/null
  run "$HANDSSHAKE_SCRIPT" add "$dummy_key1"
  assert_success
  run "$HANDSSHAKE_SCRIPT" add "$dummy_key2"
  assert_success

  # Run remove-all
  run "$HANDSSHAKE_SCRIPT" remove-all
  assert_success
  assert_output --partial "All keys removed"

  # Verify the record file is effectively empty or gone
  # The atomic write might recreate it empty or delete it. 
  # Code says `clear_records` does `rm -f`.
  [ ! -f "$STATE_DIR/added_keys.list" ]
  
  # Verify agent has no keys
  if [ -f "$STATE_DIR/ssh-agent.env" ]; then
      source "$STATE_DIR/ssh-agent.env"
      run ssh-add -l
      assert_output --partial "The agent has no identities."
  fi
}

@test "refactor: timeout command should update timeouts" {
  # Add a key
  local dummy_key="$BATS_TMPDIR/dummy_key"
  ssh-keygen -t rsa -b 2048 -f "$dummy_key" -N "" >/dev/null
  run "$HANDSSHAKE_SCRIPT" add "$dummy_key"
  assert_success
  
  # Update timeout
  run "$HANDSSHAKE_SCRIPT" timeout 1800
  assert_success
  assert_output --partial "Timeout updated for '$dummy_key'"
}

@test "refactor: concurrent add calls should not corrupt state" {
  local dummy_key1="$BATS_TMPDIR/concurrent_key1"
  local dummy_key2="$BATS_TMPDIR/concurrent_key2"
  ssh-keygen -t rsa -b 2048 -f "$dummy_key1" -N "" -C "concurrent_key1" >/dev/null
  ssh-keygen -t rsa -b 2048 -f "$dummy_key2" -N "" -C "concurrent_key2" >/dev/null
  
  # Run two 'add' commands in the background simultaneously
  "$HANDSSHAKE_SCRIPT" add "$dummy_key1" &
  pid1=$!
  "$HANDSSHAKE_SCRIPT" add "$dummy_key2" &
  pid2=$!
  
  # Wait for both to finish
  wait $pid1
  wait $pid2
  
  # Check the record file for both keys
  # There should be exactly two non-empty lines
  local line_count
  line_count=$(grep -c . "$STATE_DIR/added_keys.list")
  assert_equal "$line_count" 2
  run grep -Fq "$dummy_key1" "$STATE_DIR/added_keys.list"
  assert_success
  run grep -Fq "$dummy_key2" "$STATE_DIR/added_keys.list"
  assert_success
  
  # Check the agent for both keys
  if [ -f "$STATE_DIR/ssh-agent.env" ]; then
      source "$STATE_DIR/ssh-agent.env"
      run ssh-add -l
      assert_output --partial "concurrent_key1"
      assert_output --partial "concurrent_key2"
  fi
}
