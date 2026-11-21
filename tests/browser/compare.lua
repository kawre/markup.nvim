-- Run from the repository root after make build.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require("markup")

local ref = dofile("tests/browser/reference.lua")

local function compare(case)
	local browser_layout = ref.reference(case)
	local win =
		Markup.window({ width = case.width, height = 10, border = "none", backdrop = false })
	local view = Markup.view(win)
	assert(view:columns() == case.width, "Neovim viewport width differs from fixture")
	view:render(case.tree)
	local actual = ref.snapshot(view.engine)
	local lines = case.check_text and vim.api.nvim_buf_get_lines(win.buf, 0, -1, false)
	view:destroy()
	win:destroy()
	return ref.compare(browser_layout, actual, lines)
end

local cases = dofile(arg[1] or "tests/browser/cases.lua")
local failures = 0
for _, case in ipairs(cases) do
	local ok, result, reason = pcall(compare, case)
	if ok and result == "unsupported" then
		print(("SKIP %s: %s"):format(case.name, reason))
	else
		print(("%s %s%s"):format(ok and "PASS" or "FAIL", case.name, ok and "" or "\n  " .. result))
	end
	if not ok then
		failures = failures + 1
	end
end
ref.close()
assert(failures == 0, ("%d of %d browser comparisons failed"):format(failures, #cases))
