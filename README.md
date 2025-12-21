# handsshake

`handsshake` is a robust SSH agent manager designed to provide persistence, timeout features, and concurrency safety for your SSH keys. It ensures your SSH agent remains active across multiple terminal sessions and allows you to manage key lifetimes effectively.

## Key Features

- **Persistent SSH Agent**: Reuses the same SSH agent across multiple shell sessions by tracking the agent's PID and socket, preventing agent sprawl.
- **Key Management**: Simple commands to add, remove, and list SSH keys. Supports removing all keys at once.
- **Configurable Timeouts**: Enforces a default timeout for keys (default 24h) to enhance security.
- **Concurrency Safety**: Utilizes file locking (`flock`) to prevent race conditions when multiple shell instances attempt to modify the agent state or key records simultaneously.
- **Atomic State Updates**: Ensures that updates to the agent environment files and key records are performed atomically to prevent data corruption.

## Installation & Usage

### Installation

1.  **Download**: Clone the repository or place the `handsshake` project in a stable directory (e.g., `~/handsshake`).

2.  **Shell Configuration**: To ensure the SSH agent environment variables are loaded into every shell session, source the main script in your `.bashrc` or `.zshrc`.

    Add the following lines to your shell configuration file:

    ```bash
    # Set the path to the handsshake script
    export HANDSSHAKE_HOME="$HOME/handsshake" # Adjust path as necessary

    # Initialize the SSH agent and export environment variables
    # We run 'list' to ensure the agent is started/checked without performing changes
    source "$HANDSSHAKE_HOME/src/core/main.sh" list > /dev/null 2>&1

    # Create an alias for easy management
    # Using 'source' ensures the script runs in the current shell context
    alias handsshake='source "$HANDSSHAKE_HOME/src/core/main.sh"'
    ```

3.  **Reload Shell**: Run `source ~/.bashrc` (or `~/.zshrc`) or restart your terminal.

### Usage

Once installed and aliased, you can use the `handsshake` command to manage your keys.

**Add a key:**
Adds a key to the agent with the configured default timeout.

```bash
handsshake add ~/.ssh/id_rsa
```

**Remove a key:**
Removes a specific key from the agent and the persistent record.

```bash
handsshake remove ~/.ssh/id_rsa
```

**Remove all keys:**
Removes all keys from the agent and clears the persistent record.

```bash
handsshake remove-all
```

**List keys:**
Lists the keys currently managed by the agent.

```bash
handsshake list
```

**Update timeout:**
Updates the timeout for all currently recorded keys. This removes and re-adds the keys with the new timeout value.

```bash
handsshake timeout 7200
```

## Configuration

`handsshake` adheres to the **XDG Base Directory Specification**.

- **Config File**: `${XDG_CONFIG_HOME:-$HOME/.config}/handsshake/settings.conf`
- **State Directory**: `${XDG_STATE_HOME:-$HOME/.local/state}/handsshake/`
  - **Logs**: `logs/handsshake.log`
  - **Agent Env**: `ssh-agent.env`
  - **Key Record**: `added_keys.list`

You can modify the following variables in your `settings.conf`:

- **`HANDSSHAKE_DEFAULT_TIMEOUT`**: The default duration (in seconds) that keys will remain active. Default is `86400` (24 hours).
- **`HANDSSHAKE_VERBOSE`**: Set to `true` for detailed logging, or `false` for minimal output.

## Development

The project includes a `Makefile` for automated code quality checks.

- **`make lint-shell`**: Run `shellcheck` on all scripts.
- **`make format-shell`**: Auto-format code using `shfmt`.
- **`make format-check`**: Check if code is properly formatted.
- **`make check-line-length`**: Ensure no lines exceed 80 characters.
- **`make ci`**: Run all linting and line-length checks.

To run tests, use [BATS](https://github.com/bats-core/bats-core):
```bash
bats test/
```

## Directory Structure

- **`src/core/`**: Main entry point (`main.sh`).
- **`src/services/`**: Service logic modules (key management, agent lifecycle).
- **`src/lib/`**: Shared library scripts (configuration, constants).
- **`src/util/`**: Utility modules (file operations, logging, validation).
- **`test/`**: BATS test suite.
