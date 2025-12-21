# Troubleshooting Log: SSH Agent Persistence & Shell Integration

This document records the major issues encountered during the development of shell integration for `handsshake` and how they were resolved.

## 1. Environment Propagation (The Subshell Trap)

**Issue**: Running `handsshake` as a standard executable (`./handsshake`) created a subshell. Any `SSH_AUTH_SOCK` or `SSH_AGENT_PID` variables set inside the script were lost the moment the script finished, leaving applications like Neovim unable to find the agent.

**Solution**: The application was refactored to be **sourced** (`source handsshake.sh`). This allows the script to inject variables directly into the user's active shell environment.

## 2. Shell Termination (Exit vs. Return)

**Issue**: When a script is sourced, the `exit` command terminates the **entire terminal window**, not just the script. Initial versions of `handsshake` used `exit 1` for error handling, which caused the user's shell to close unexpectedly.

**Solution**:

- Replaced all instances of `exit` with `return`.
- Added a robust check at the top of `main.sh` to warn users if they execute the script instead of sourcing it.

## 3. The `readonly` Variable Lock

**Issue**: Bash variables marked as `readonly` cannot be modified or redefined in the same session. When the script was sourced multiple times (e.g., reloading `.bashrc`), it attempted to redefine core variables like `SCRIPT_DIR` and `LOG_FILE`, causing "readonly variable" errors and preventing the script from loading correctly.

**Solution**:

- **Namespacing**: Every global variable was renamed with a `HANDSSHAKE_` prefix (e.g., `HANDSSHAKE_LOG_FILE`). This prevented collisions with common shell variable names.
- **Lock Removal**: All `readonly` keywords were removed from top-level declarations to ensure the script is fully idempotent (can be sourced safely any number of times).
- **Loading Guards**: Added `if [[ -z "${HANDSSHAKE_LOADED:-}" ]]` guards to every module to ensure they only initialize their state once per session.

## 4. Reachability vs. Identities (The Contradiction)

**Issue**: `handsshake health` reported an `ERROR` status while `handsshake list` reported "no identities". This was because `ssh-add -l` returns exit code `1` when the agent is alive but empty. The health check was incorrectly treating any non-zero exit code as a connection failure.

**Solution**: Refined the logic to check specific exit codes for `ssh-add -l`:

- `0`: Agent alive, keys found.
- `1`: Agent alive, no keys found.
- `2`: Agent unreachable.

## Summary of Final State

The application now uses a strict naming convention and robust sourcing guards. It is safe to use in `.bashrc` or `.zshrc` and provides accurate diagnostics via the `health` command.
