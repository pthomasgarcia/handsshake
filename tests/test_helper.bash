#!/usr/bin/env bash
# shellcheck shell=bash

# tests/test_helper.bash
# Global test orchestrator for Handsshake

# --- 1. Path Resolution ---
# Locates the test and project root directories
_TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PROJECT_ROOT="$(cd "$_TEST_ROOT/.." && pwd)"
_TEST_LIB="$_TEST_ROOT/lib"

# --- 2. Load BATS Libraries (Vendor) ---
# Load standard BATS assertions and support from your new vendor location
# shellcheck disable=SC1091
load "lib/vendor/bats-support/load.bash"
load "lib/vendor/bats-assert/load.bash"

# --- 3. Load Internal Test Helpers ---
# These provide the namespaces for agents::, keys::, and env:: within tests
# shellcheck disable=SC1091
source "$_TEST_LIB/env.bash"
source "$_TEST_LIB/keys.bash"
source "$_TEST_LIB/agent.bash"

# --- 4. Global Initialization ---
# Prepare the tracking environment before any tests run
init_env

# --- 5. BATS Lifecycle Hooks ---
# These functions are automatically recognized by BATS
setup() {
    # Set up a clean sandbox for EVERY test case
    setup_test_env
}

teardown() {
    # Clean up the sandbox after EVERY test case
    teardown_test_env
}
