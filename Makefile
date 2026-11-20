.PHONY: build test test_lua test_engine test_file format format_check lint coverage coverage_lua coverage_rust

NVIM_TEST = nvim --headless --noplugin -u ./scripts/minimal_init.lua
ROCKS = .tests/rocks
COVERAGE_TIMEOUT ?= 20m
# The least coverage, in percent, of the Lua and of the Rust
COVERAGE_MIN ?= 80
# How many test files run at once under coverage
JOBS ?= $(shell nproc 2>/dev/null || echo 2)

# Build the native engine
build:
	cargo build --release

# Run all test files
test: build test_lua

# Run all test files on the engine already built, as CI does with a downloaded one
test_lua: deps/mini.test
	$(NVIM_TEST) -c "lua MiniTest.run()"

# Run the engine's unit tests
test_engine:
	cargo test

# Run test from file at `$FILE` environment variable
test_file: deps/mini.test build
	$(NVIM_TEST) -c "lua MiniTest.run_file('$(FILE)')"

# Format Lua and Rust in place
format:
	stylua lua tests scripts
	cargo fmt

# Fail when anything is not formatted
format_check:
	stylua --check lua tests scripts
	cargo fmt --check

# Lint the engine
lint:
	cargo clippy --all-targets -- -D warnings

# Coverage of both halves, in .tests/coverage
coverage: coverage_lua coverage_rust

# Lua coverage of the test suite, as LCOV in .tests/coverage/lua.lcov
# With SKIP_BUILD=1, on the engine already built, as CI does with a downloaded one
coverage_lua: deps/mini.test $(if $(SKIP_BUILD),,build) $(ROCKS)
	rm -rf .tests/coverage/luacov.stats.* .tests/coverage/logs
	@mkdir -p .tests/coverage/logs
	@# The files at once, on every core, the largest first so the cores finish
	@# together. Each Neovim writes stats of its own and each file a log of its
	@# own. A file that passes takes one line; one that fails or runs past the
	@# limit shows its whole log, with each case as it ran, and the others
	@# still count.
	@ls -S tests/test_*.lua | xargs -P $(JOBS) -I{} sh -c '\
		log=.tests/coverage/logs/$$(basename {}).log; \
		if MARKUP_COVERAGE=1 MARKUP_TEST_TRACE=1 timeout $(COVERAGE_TIMEOUT) \
			$(NVIM_TEST) -c "lua MiniTest.run_file(\"{}\")" > $$log 2>&1; then \
			echo "ok {}: $$(sed "s/\x1b\[[0-9;]*m//g" $$log | grep -a "^Fails" | tail -n 1)"; \
		else \
			echo "!! {} failed or ran past $(COVERAGE_TIMEOUT)" >> $$log; \
			echo "== {}"; cat $$log; \
		fi'
	@failed=0; grep -l '^!! ' .tests/coverage/logs/*.log >/dev/null 2>&1 && failed=1; \
	MARKUP_COVERAGE_MIN=$(COVERAGE_MIN) nvim -l scripts/coverage.lua || failed=1; \
	exit $$failed

# Rust coverage of the engine's unit tests, as LCOV in .tests/coverage/rust.lcov
coverage_rust:
	@mkdir -p .tests/coverage
	cargo llvm-cov --lcov --output-path .tests/coverage/rust.lcov
	cargo llvm-cov report --summary-only --fail-under-lines $(COVERAGE_MIN)

# LuaCov, in a tree of the project's own
$(ROCKS):
	luarocks --lua-version 5.1 --tree $(ROCKS) install luacov
	luarocks --lua-version 5.1 --tree $(ROCKS) install luacov-reporter-lcov

# Download 'mini.nvim' to use its 'mini.test' testing module
deps/mini.test:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/echasnovski/mini.test $@
