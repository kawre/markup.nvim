.PHONY: build test test_lua test_engine test_file format format_check lint coverage coverage_lua coverage_rust

NVIM_TEST = nvim --headless --noplugin -u ./scripts/minimal_init.lua
ROCKS = .tests/rocks
COVERAGE_TIMEOUT ?= 5m

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
coverage_lua: deps/mini.test build $(ROCKS)
	rm -f .tests/coverage/luacov.stats.*
	@# A file at a time, each with a time limit, so one that hangs is named and
	@# the rest still count.
	@failed=0; for file in tests/test_*.lua; do \
		echo "== $$file"; \
		MARKUP_COVERAGE=1 timeout $(COVERAGE_TIMEOUT) $(NVIM_TEST) -c "lua MiniTest.run_file('$$file')" \
			|| { echo "!! $$file failed or ran past $(COVERAGE_TIMEOUT)"; failed=1; }; \
	done; \
	nvim -l scripts/coverage.lua; \
	exit $$failed

# Rust coverage of the engine's unit tests, as LCOV in .tests/coverage/rust.lcov
coverage_rust:
	@mkdir -p .tests/coverage
	cargo llvm-cov --lcov --output-path .tests/coverage/rust.lcov
	cargo llvm-cov report --summary-only

# LuaCov, in a tree of the project's own
$(ROCKS):
	luarocks --lua-version 5.1 --tree $(ROCKS) install luacov
	luarocks --lua-version 5.1 --tree $(ROCKS) install luacov-reporter-lcov

# Download 'mini.nvim' to use its 'mini.test' testing module
deps/mini.test:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/echasnovski/mini.test $@
