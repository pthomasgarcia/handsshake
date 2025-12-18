# handsshake Architecture Redesign Proposal

## 1. Current Architecture Analysis

### Overview
The current project is a Bash-based SSH agent manager structured into modular components (`core`, `common`, `aux`). `src/core/main.sh` serves as the entry point, orchestrating configuration loading, environment validation, and key management.

### Strengths
*   **Modularity**: The codebase is already split into logical units (logging, validation, config), avoiding a single monolithic script.
*   **Static Analysis**: The code uses `shellcheck` directives, indicating a commitment to code quality.
*   **Dependency-Free**: Relies only on standard Linux utilities (`ssh-agent`, `ssh-add`, `awk`, `grep`), ensuring high portability.

### Weaknesses & Bottlenecks
*   **Logic Coupling**: `src/core/main.sh` handles too many responsibilities: CLI argument parsing, high-level flow control, and specific business logic (like key timeout updates).
*   **State Management**: The system relies on flat files (`ssh-agent.env`, `added_keys.list`) for state.
    *   **Race Conditions**: There is no file locking mechanism. If two terminal instances initialize `handsshake` simultaneously, they might corrupt the state files or spawn orphan agents.
*   **Path Dependency**: The script calculates `SCRIPT_DIR` relative to itself. While common, this can be fragile if symlinked or executed in unusual contexts.
*   **Error Handling**: While `error_exit` exists, error propagation relies on exit codes which can be brittle in complex Bash call chains.

## 2. Proposed Architectural Improvements

### Option A: Refactored Bash Architecture
If the project is to remain in Bash, we should adopt a stricter "Library vs Executable" pattern to improve maintainability and robustness.

#### Directory Structure
```text
bin/
  handsshake          # Thin executable wrapper (sets paths, calls entry)
lib/
  cli/                # Argument parsing and command routing
  services/           # Business logic
    agent_manager.sh  # Managing ssh-agent process and env file
    key_manager.sh    # Managing ssh-add and key records
  utils/              # Low-level helpers
    lock_utils.sh     # NEW: File locking implementation
    file_utils.sh
    log_utils.sh
config/               # Default configuration templates
tests/                # BATS test suite
```

#### Key Improvements
1.  **Concurrency Control (Locking)**: Implement a `with_lock` utility using `flock` (file locking) to wrap all writes to `added_keys.list` and `ssh-agent.env`. This prevents race conditions.
2.  **Service Layer**: Extract logic from `main.sh`.
    *   `agent_manager.sh`: Responsible solely for `start_agent`, `ensure_agent`, `kill_agent`.
    *   `key_manager.sh`: Responsible for `add_key`, `remove_key`, `audit_keys`.
3.  **Standardized State Paths**: Instead of storing state relative to the script, adhere to XDG Base Directory specs (e.g., `~/.local/state/handsshake/` or `~/.cache/handsshake/`) or a configurable `HANDSSHAKE_HOME`.

### Option B: Alternative Language (Python)
Given the complexity of process management (PIDs, signals) and state persistence, Python is a strong candidate.

#### Why Python?
*   **Process Management**: The `subprocess` module provides robust control over spawning and killing agents, capturing output, and handling timeouts.
*   **State Handling**: JSON or SQLite can be used for state, which is safer and easier to parse than line-delimited files.
*   **Locking**: Built-in support for file locking (via `fcntl` or libraries) makes concurrency control trivial.
*   **Argument Parsing**: `argparse` or `click` libraries handle CLI complexity far better than Bash `case` statements.

#### Comparison
| Feature | Bash (Refactored) | Python |
| :--- | :--- | :--- |
| **Portability** | High (Any Linux/Unix) | High (Requires Python runtime) |
| **Performance** | Fast startup | Slower startup (negligible here) |
| **Maintainability** | Medium (Bash quirks) | High (Readable, structured) |
| **Complexity** | Harder to handle complex state | Easy to handle complex state |

## 3. Recommendation
**Refactor in Bash** if the primary goal is a lightweight, zero-dependency tool for personal use on Linux servers. The overhead of Python might not be justified for wrapping `ssh-agent`.

**Switch to Python** if you plan to add features like:
*   Cross-platform support (macOS/Linux unified logic).
*   Complex key rotation policies.
*   Integration with other APIs (e.g., fetching keys from a vault).

## 4. Implementation Roadmap

### Phase 1: Foundation (Immediate)
1.  **Test Coverage**: specific existing functionality in `test/` using BATS. Ensure we have a baseline.
2.  **Directory Restructure**: Move files into the new `lib/`, `bin/` structure. Update `source` paths.

### Phase 2: Core Refactoring
3.  **Implement Locking**: Create `src/aux/lock_utils.sh` implementing `flock`.
4.  **Extract Services**:
    *   Move `start_agent`, `ensure_agent` to `lib/services/agent_manager.sh`.
    *   Move `add_key`, `list_keys` to `lib/services/key_manager.sh`.
5.  **Update Entry Point**: Rewrite `main.sh` to simply parse args and call the appropriate service function, wrapping operations in locks where necessary.

### Phase 3: Enhancements
6.  **XDG Compliance**: Update configuration to use standard user directories for state files.
7.  **Robust Error Handling**: Replace `exit 1` with specific error codes and trap handlers for cleanup (e.g., releasing locks).