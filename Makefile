SHELL := /usr/bin/env bash

# Flags kept in one place to match CI exactly
# -i 4 = 4 spaces per indent for normal blocks
# -ci = indent switch cases
# -sr = simplify redirects
# -ln bash = enforce Bash mode
# -kp = keep existing indentation on continuation lines
SHFMT_FLAGS := -i 4 -ci -sr -ln bash
SHELLCHECK_FLAGS := -S style -x

.PHONY: lint-shell format-shell format-check check-line-length ci tools

# Optional: verify tools exist locally
tools:
	@command -v shellcheck >/dev/null || { echo "shellcheck not found"; exit 1; }
	@command -v shfmt >/dev/null || { echo "shfmt not found"; exit 1; }

lint-shell: tools
	@mapfile -t files < <(git ls-files '*.sh'); \
	if [ "$${#files[@]}" -eq 0 ]; then \
		echo "No shell scripts found."; \
	else \
		shellcheck $(SHELLCHECK_FLAGS) "$${files[@]}"; \
	fi

# Check line length (80 chars limit)
check-line-length: tools
	@echo "Checking line lengths (max 80 characters)..."
	@mapfile -t files < <(git ls-files '*.sh' | grep -v 'test/test_helper'); \
	if [ "$${#files[@]}" -eq 0 ]; then \
		echo "No shell scripts found."; \
	else \
		errors=0; \
		for file in "$${files[@]}"; do \
			long_lines=$$(grep -n ".\{81,\}" "$$file"); \
			if [ -n "$$long_lines" ]; then \
				echo "File $$file has lines exceeding 80 characters:"; \
				echo "$$long_lines"; \
				errors=1; \
			fi; \
		done; \
		if [ "$$errors" -eq 1 ]; then \
			exit 1; \
		fi; \
		echo "All lines are within 80 characters."; \
	fi

# Check formatting (no write)
format-check: tools
	@mapfile -t files < <(git ls-files '*.sh' | grep -v 'test/test_helper'); \
	if [ "$${#files[@]}" -eq 0 ]; then \
		echo "No shell scripts found."; \
	else \
		shfmt -d $(SHFMT_FLAGS) "$${files[@]}"; \
	fi

# Auto-format locally
format-shell: tools
	@mapfile -t files < <(git ls-files '*.sh' | grep -v 'test/test_helper'); \
	if [ "$${#files[@]}" -eq 0 ]; then \
		echo "No shell scripts found."; \
	else \
		shfmt -w $(SHFMT_FLAGS) "$${files[@]}"; \
	fi

# CI target
ci: lint-shell check-line-length format-check
	@echo "CI checks passed."
