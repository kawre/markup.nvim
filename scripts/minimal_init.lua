-- Add current directory to 'runtimepath' to be able to use 'lua' files
vim.cmd([[let &rtp.=','.getcwd()]])

-- Collect Lua coverage with LuaCov when `MARKUP_COVERAGE` is set (`make coverage`).
-- Every Neovim, the test runner and each child, writes stats of its own, which
-- `scripts/coverage.lua` merges into one report.
if vim.env.MARKUP_COVERAGE then
	local tree = vim.env.MARKUP_ROCKS or (vim.fn.getcwd() .. "/.tests/rocks")
	package.path = ("%s/share/lua/5.1/?.lua;%s/share/lua/5.1/?/init.lua;"):format(tree, tree)
		.. package.path
	-- Line hooks only run in the interpreter, compiled traces would skip them.
	jit.off(true, true)
	local runner = require("luacov.runner")
	vim.fn.mkdir(".tests/coverage", "p")
	runner.init({
		statsfile = (".tests/coverage/luacov.stats.%d.out"):format(vim.fn.getpid()),
		include = { "lua/markup/" },
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			runner.save_stats()
		end,
	})
end

-- Set up 'mini.test' only when calling headless Neovim (like with `make test`)
if #vim.api.nvim_list_uis() == 0 then
	-- Add 'mini.nvim' to 'runtimepath' to be able to use 'mini.test'
	-- Assumed that 'mini.nvim' is stored in 'deps/mini.nvim'
	vim.cmd("set rtp+=deps/mini.test")

	-- Set up 'mini.test'
	require("mini.test").setup()

	-- With `MARKUP_TEST_TRACE`, name every case as it starts and ends, on stderr
	-- and at once, so a case that hangs is named even when the output is piped.
	if vim.env.MARKUP_TEST_TRACE then
		local stdout = MiniTest.gen_reporter.stdout()
		local seen = {}
		MiniTest.config.execute.reporter = {
			start = stdout.start,
			finish = stdout.finish,
			update = function(id)
				stdout.update(id)
				local case = MiniTest.current.all_cases[id]
				local state = case.exec and case.exec.state or "start"
				if seen[id] ~= state then
					seen[id] = state
					io.stderr:write(
						("[%s] %s: %s\n"):format(
							os.date("%H:%M:%S"),
							table.concat(case.desc, " | "),
							state
						)
					)
					io.stderr:flush()
				end
			end,
		}
	end
end
