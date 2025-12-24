# handsshake

> One SSH agent to rule them all — persistent, secure, and drama-free.

## Why handsshake?

If you've ever had:

- **Agent sprawl**: Multiple `ssh-agent` processes eating memory
- **"Permission denied"**: Shell sessions that can't see your keys
- **Timeout whack-a-mole**: Keys vanishing mid-workflow
- **Zombie agents**: Orphaned processes you have to `pkill` by hand

Then handsshake is for you.
It keeps **one** agent alive, makes it visible to **every** shell, and lets you set **TTLs** so keys don't live forever.

---

## ⚡ One-line install

```bash
git clone https://github.com/your-username/handsshake.git ~/.handsshake
echo 'alias handsshake="source ~/.handsshake/src/core/main.sh"' >> ~/.bashrc
exec $SHELL   # reload
```

That's it. `handsshake list` will auto-start the agent on first run.

---

## 📖 Cheat-sheet

| Command                          | What it does                             |
| -------------------------------- | ---------------------------------------- |
| `handsshake attach [key]`        | Add a key (default: `~/.ssh/id_ed25519`) |
| `handsshake detach <key>`        | Remove a key                             |
| `handsshake list`                | Show fingerprints                        |
| `handsshake flush`               | Nuke **everything** from the agent       |
| `handsshake timeout <key> <sec>` | Set TTL for **one** key                  |
| `handsshake timeout --all 3600`  | Set **1 h** TTL on **all** keys          |
| `handsshake health`              | Diagnose setup                           |
| `handsshake cleanup`             | Kill agent + wipe state                  |

> Shell-agnostic: works in `bash`, `zsh`, `fish`, _etc._

---

## 🛠️ Quick config

Drop a file at `$XDG_CONFIG_HOME/handsshake/settings.conf` or export:

```bash
export HANDSSHAKE_DEFAULT_TIMEOUT=43200  # 12 h
export HANDSSHAKE_VERBOSE=true           # chatty logs
```

| Variable                     | Default             | Purpose            |
| ---------------------------- | ------------------- | ------------------ |
| `HANDSSHAKE_DEFAULT_TIMEOUT` | `86400` (24 h)      | Key TTL in seconds |
| `HANDSSHAKE_VERBOSE`         | `false`             | Debug output       |
| `HANDSSHAKE_DEFAULT_KEY`     | `~/.ssh/id_ed25519` | Fallback key       |

---

## 🧪 Develop & test

```bash
git clone https://github.com/your-username/handsshake.git && cd handsshake
make ci          # lint + format + test
make test        # bats suite only
```

Needs: `bash 4.4+`, `flock`, `ssh-agent`, `make`, `bats`.

---

## 📄 License

MIT © 2025 contributors
