# shellcheck shell=bash

# tests/test_helper/common_setup.bash
# Orchestrates test setup by loading modular helpers

# Resolve the directory of this script to find libs
_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LIB_DIR="$_HELPER_DIR/../lib"

# Load modular helpers
# shellcheck source=../lib/env.bash
# shellcheck disable=SC1091
source "$_LIB_DIR/env.bash"
# shellcheck source=../lib/keys.bash
# shellcheck disable=SC1091
source "$_LIB_DIR/keys.bash"
# shellcheck source=../lib/agent.bash
# shellcheck disable=SC1091
source "$_LIB_DIR/agent.bash"

# Initialize environment tracking
init_env

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}
