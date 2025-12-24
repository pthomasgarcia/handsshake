# handsshake

> A robust and persistent SSH agent manager.

`handsshake` is a shell-agnostic SSH agent manager designed to eliminate agent sprawl and improve security. It ensures a single SSH agent instance persists across multiple terminal sessions, enforcing timeouts and ensuring safe concurrent operation.

## Key Features

- **Persistence**: Reuses a single `ssh-agent` process across all shell instances.
- **Concurrency**: Works seamlessly across multiple open terminal sessions.
- **Security**: Enforces configurable TTL (Time-To-Live) for added keys.
- **Idempotency**: Safe to source multiple times without side effects.
- **XDG Compliance**: Follows XDG Base Directory standards for config and state.

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/your-username/handsshake.git ~/.handsshake
```

### 2. Update Shell Configuration

Add the following to your `.bashrc` or `.zshrc` to automatically initialize the agent on shell startup:

```bash
# Initialize handsshake
alias handsshake='source $HOME/.handsshake/src/core/main.sh'
handsshake list > /dev/null 2>&1
```

> **Note**: The `handsshake` alias uses `source` to ensure environment variables like `SSH_AUTH_SOCK` and `SSH_AGENT_PID` are correctly exported to your current shell.

## Usage

| Command                          | Description                                            |
| -------------------------------- | ------------------------------------------------------ |
| `handsshake attach [key]`        | Add a key to the agent (default: `~/.ssh/id_ed25519`). |
| `handsshake detach <key>`        | Remove a specific key from the agent.                  |
| `handsshake list`                | List fingerprints of all currently attached keys.      |
| `handsshake keys`                | Show public keys of attached identities.               |
| `handsshake flush`               | Remove all keys from the agent.                        |
| `handsshake timeout <key> <sec>` | Update timeout for a specific key.                     |
| `handsshake timeout --all <sec>` | Update global timeout for all tracked keys.            |
| `handsshake health`              | Verify environment health and permissions.             |
| `handsshake version`             | Show version information.                              |
| `handsshake cleanup`             | Kill the agent and clean up all state files.           |

### Examples

**Add your default key:**

```bash
handsshake attach
```

**Set a 1-hour timeout for a specific key:**

```bash
handsshake timeout ~/.ssh/id_rsa 3600
```

**Verify setup:**

```bash
handsshake health
```

## Configuration

Configuration is managed via environment variables or a config file located at `$XDG_CONFIG_HOME/handsshake/settings.conf`.

| Variable | Default | Description |
| மொ | ------- | ----------- |
| `HANDSSHAKE_DEFAULT_TIMEOUT` | `86400` | Key lifetime in seconds (24 hours). |
| `HANDSSHAKE_VERBOSE` | `false` | Enable verbose logging for debugging. |
| `HANDSSHAKE_DEFAULT_KEY` | `~/.ssh/id_ed25519` | Default key to attach if none specified. |

## Development

The project ensures code quality using `shellcheck` (linting), `shfmt` (formatting), and `bats` (testing).

To run the full CI suite locally:

```bash
make ci
```

### Requirements

- `bash` 4.4+
- `flock` (util-linux)
- `ssh-agent`
- `make` (for development)
- `bats` (for testing)

## License

MIT &copy; 2025 handsshake contributors.
