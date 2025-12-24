# shellcheck shell=bash

# tests/lib/agent.bash

verify_agent_contains_key() {
    local key_comment="$1"
    if [[ -f "$STATE_DIR/ssh-agent.env" ]]; then
        # shellcheck source=/dev/null
        source "$STATE_DIR/ssh-agent.env"
        run ssh-add -l
        assert_output --partial "$key_comment"
    fi
}

verify_agent_empty() {
    if [[ -f "$STATE_DIR/ssh-agent.env" ]]; then
        # shellcheck source=/dev/null
        source "$STATE_DIR/ssh-agent.env"
        run ssh-add -l
        [[ "$status" -ne 0 ]]
    fi
}
