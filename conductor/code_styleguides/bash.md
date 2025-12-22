# Bash Style Guide - handsshake

## General Principles
- **Shebang:** Always use `#!/usr/bin/env bash`.
- **Safety Flags:** Use `set -euo pipefail` to ensure scripts exit on errors, undefined variables, and pipe failures.
- **Indentation:** Use 2 spaces for indentation (consistent with `shfmt`).
- **Line Length:** Aim for a maximum of 80 characters per line.

## Variables and Constants
- **Quoting:** Always quote variable expansions to prevent word splitting and globbing: `"$VARIABLE"`.
- **Naming:**
    - Use `UPPER_CASE` for global constants and environment variables.
    - Use `lower_case` or `snake_case` for local variables and function names.
- **Scope:** Always use the `local` keyword for variables inside functions to avoid polluting the global namespace.

## Functions
- **Declaration:** Use the format `function_name() { ... }`.
- **Documentation:** Provide a brief comment above each function explaining its purpose, arguments, and return values.
- **Return Values:** Use `return` for status codes (0 for success, non-zero for failure). Use `echo` or `printf` to return data.

## Control Flow
- **Conditions:** Prefer `[[ ... ]]` over `[ ... ]` or `test` for string and file comparisons.
- **Command Substitution:** Use `$(command)` instead of backticks.
- **Loops:** Prefer `while` loops for reading file content or command output line-by-line.

## Tools and Quality
- **ShellCheck:** All scripts must pass `shellcheck` without warnings.
- **shfmt:** Use `shfmt -i 2 -ci` for consistent formatting.
- **Testing:** New functionality must be accompanied by BATS tests in the `test/` directory.
