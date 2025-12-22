# Initial Concept
A robust SSH agent manager designed to provide persistence, timeout features, and concurrency safety for your SSH keys.

# Product Guide - handsshake

## Vision
handsshake gives you a single, locked, timeout-aware entry point to your SSH agent. One agent, no races, and keys disappear when you want them to.

## Target Users
Developers, DevOps engineers, and System Administrators who frequently manage multiple SSH keys across terminal sessions or CI/CD pipelines and need a reliable, persistent, and secure way to handle their SSH agent.

## Core Goals & Problems Solved
- **Prevent Agent Sprawl:** Ensures only one SSH agent is active per socket path, reusing it across all shell sessions to save resources and simplify management.
- **Enforce Key Security:** Eliminates the risk of keys remaining in memory indefinitely by enforcing strict, configurable timeouts.
- **Ensure Concurrency Safety:** Uses file locking to prevent race conditions and state corruption when multiple terminal instances or background jobs interact with the SSH agent simultaneously.

## Key Features
- **Persistent SSH Agent:** Reuses agent state across multiple shell sessions.
- **Locked Operations:** All mutations are protected by `flock` to prevent race conditions and corrupted agent state.
- **Timeout Management:** Configurable per-key lifetimes (1 s – 24 h) with automatic expiration and visible remaining-time in `list`.
- **Atomic State Updates:** Ensures reliability of agent environment files and key records.
