# Tech Stack - handsshake

## Core Technologies
- **Language:** Bash (Bourne Again SHell) - Primary language for all logic and utility scripts.
- **Testing:** BATS (Bash Automated Testing System) - Used for unit and integration testing of shell scripts.
- **Build & Task Automation:** Makefile - Orchestrates linting, formatting, and testing workflows.

## Essential Utilities
- **SSH Management:** `ssh-agent`, `ssh-add` - Standard tools for managing SSH keys and agents.
- **Concurrency Control:** `flock` - Linux utility for managing file locks to ensure safe concurrent operations.
- **Code Quality:** 
    - `shellcheck` - Static analysis tool for shell scripts.
    - `shfmt` - Shell script formatter.

## Project Structure
- `src/core/`: Main entry point and core logic.
- `src/services/`: Specialized service modules (e.g., key management, agent lifecycle).
- `src/lib/`: Shared configuration and constants.
- `src/util/`: General-purpose utility functions.
- `test/`: BATS-based test suite and helpers.
