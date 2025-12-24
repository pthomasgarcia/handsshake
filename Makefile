SHELL := /usr/bin/env bash

# --- Variables ---
# Finds all relevant shell files, excluding the test helper directory
SHELL_FILES       := $(shell git ls-files '*.sh' '*.bash' | grep -v 'tests/test_helper')
ALL_SHELL_FILES   := $(shell git ls-files '*.sh' '*.bash' '*.bats' | grep -v 'tests/test_helper')

# Flags
SHFMT_FLAGS      := -i 4 -ci -sr -ln bash
SHELLCHECK_FLAGS := -S style -x -s bash
COVERAGE_DIR     := coverage
KCOV_FLAGS       := --include-pattern=$(PWD) --exclude-pattern=tests/,/usr/

# --- Targets ---
.PHONY: lint-shell format-shell format-check check-line-length ci tools test coverage clean

# Verify tools exist locally
tools:
	@command -v shellcheck >/dev/null || { echo "shellcheck not found"; exit 1; }
	@command -v shfmt >/dev/null || { echo "shfmt not found"; exit 1; }
	@command -v bats >/dev/null || { echo "bats not found"; exit 1; }

# Run standard Bats tests
test: tools
	@echo "Running tests..."
	bats tests/

# Generate coverage report
coverage: tools
	@rm -rf $(COVERAGE_DIR)
	@mkdir -p $(COVERAGE_DIR)
	@echo "Running tests with coverage (kcov)..."
	kcov $(KCOV_FLAGS) $(COVERAGE_DIR) bats tests/
	@echo "Coverage report: $(COVERAGE_DIR)/index.html"

# Linting
lint-shell: tools
	@if [ -z "$(ALL_SHELL_FILES)" ]; then \
		echo "No shell scripts found."; \
	else \
		shellcheck $(SHELLCHECK_FLAGS) $(ALL_SHELL_FILES); \
		echo "ShellCheck passed."; \
	fi

# Line length check (80 chars)
check-line-length:
	@echo "Checking line lengths (max 80 characters)..."
	@errors=0; \
	for file in $(ALL_SHELL_FILES); do \
		long_lines=$$(grep -n ".\{81,\}" "$$file"); \
		if [ -n "$$long_lines" ]; then \
			echo "File $$file has lines exceeding 80 characters:"; \
			echo "$$long_lines"; \
			errors=1; \
		fi; \
	done; \
	[ $$errors -eq 0 ] || exit 1
	@echo "Line length check passed."

# Check formatting (no write) - EXCLUDE BATS
format-check: tools
	@if [ -z "$(SHELL_FILES)" ]; then \
		echo "No shell scripts found."; \
	else \
		shfmt -d $(SHFMT_FLAGS) $(SHELL_FILES); \
	fi

# Auto-format locally - EXCLUDE BATS
format-shell: tools
	@if [ -z "$(SHELL_FILES)" ]; then \
		echo "No files to format."; \
	else \
		shfmt -w $(SHFMT_FLAGS) $(SHELL_FILES); \
		echo "Formatting complete."; \
	fi

clean:
	rm -rf $(COVERAGE_DIR)

# CI target
ci: lint-shell check-line-length format-check test
	@echo "All CI checks passed."
