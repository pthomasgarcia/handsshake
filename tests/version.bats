#!/usr/bin/env bats

load "test_helper/bats-support/load.bash"
load "test_helper/bats-assert/load.bash"
load "test_helper/common_setup.bash"

@test "version command should show version" {
  run main version
  assert_success
  assert_output --regexp 'v[0-9]+\.[0-9]+\.[0-9]+'
}

@test "version with -v flag works" {
  run main -v
  assert_success
  assert_output --regexp 'v[0-9]+\.[0-9]+\.[0-9]+'
}

@test "version with --version flag works" {
  run main --version
  assert_success
  assert_output --regexp 'v[0-9]+\.[0-9]+\.[0-9]+'
}
