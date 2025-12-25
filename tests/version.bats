#!/usr/bin/env bats

load "test_helper"

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
