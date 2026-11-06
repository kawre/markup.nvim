# Build the native engine
build:
	cargo build --release

# Run all test files
test: deps/mini.test build
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"

# Run the engine's unit tests
test_engine:
	cargo test

# Run test from file at `$FILE` environment variable
test_file: deps/mini.test build
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

# Download 'mini.nvim' to use its 'mini.test' testing module
deps/mini.test:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/echasnovski/mini.test $@
