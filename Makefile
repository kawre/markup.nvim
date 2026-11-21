.PHONY: build docs luals test test_lua test_engine test_file format format_check lint coverage coverage_lua coverage_rust

NVIM_TEST = nvim --headless --noplugin -u ./scripts/minimal_init.lua
ROCKS = .tests/rocks
# lua-language-server for `make docs`. CI uses this version, so docs written
# with it are the ones CI would write.
LUALS_VERSION = 3.19.2
LUALS = .tests/luals/bin/lua-language-server
# The headers of LuaJIT, to build cluacov for it
LUAJIT_INCDIR ?= /usr/include/luajit-2.1
COVERAGE_TIMEOUT ?= 20m
# How long a test file may run without coverage
TEST_TIMEOUT ?= 10m
# The least coverage, in percent, of the Lua and of the Rust
COVERAGE_MIN ?= 80
# How many test files run at once
JOBS ?= $(shell nproc 2>/dev/null || echo 2)

# Build the native engine
build:
	cargo build --release

# Run all test files
test: build test_lua

# Run all test files on the engine already built, as CI does with a downloaded
# one: at once on every core, with a progress bar
test_lua: deps/mini.test
	@$(if $(filter 1,$(BROWSER)),scripts/run_browser_suite.sh,scripts/run_tests.sh) $(JOBS) $(TEST_TIMEOUT) $(NVIM_TEST)

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
	rm -f .tests/coverage/luacov.stats.*
	@mkdir -p .tests/coverage
	@failed=0; MARKUP_COVERAGE=1 scripts/run_tests.sh $(JOBS) $(COVERAGE_TIMEOUT) $(NVIM_TEST) || failed=1; \
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
	@# LuaCov's hook in C, built for the LuaJIT of Neovim: coverage runs
	@# several times faster with it.
	luarocks --lua-version 5.1 --tree $(ROCKS) install cluacov LUA_INCDIR=$(LUAJIT_INCDIR)

# Download 'mini.nvim' to use its 'mini.test' testing module
deps/mini.test:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/echasnovski/mini.test $@

# Write docs/, doc/markup.txt, llms.txt and skills/ from the comments in the code
docs:
	nvim -l scripts/docs.lua

# lua-language-server, at the version CI uses, in .tests/luals
luals: $(LUALS)
$(LUALS):
	@mkdir -p .tests/luals
	curl -fsSL https://github.com/LuaLS/lua-language-server/releases/download/$(LUALS_VERSION)/lua-language-server-$(LUALS_VERSION)-linux-x64.tar.gz \
		| tar xz -C .tests/luals

# Compare static layout fixtures against headless Chromium. With SHOW=1, open a
# page of what differs in a browser, or of everything with SHOW=all; this also
# works with `make test BROWSER=1`.
export SHOW
.PHONY: test_browser
test_browser: build
	nvim -u NONE -l tests/browser/compare.lua $(FILE)
