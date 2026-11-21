-- Run from the repository root after make build.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require("markup")

local ref = dofile("tests/browser/reference.lua")

local show = vim.env.SHOW ~= nil and vim.env.SHOW ~= "" and vim.env.SHOW ~= "0"
local shown = {}

local function compare(case)
	local browser_layout = ref.reference(case)
	local win =
		Markup.window({ width = case.width, height = 10, border = "none", backdrop = false })
	local view = Markup.view(win)
	assert(view:columns() == case.width, "Neovim viewport width differs from fixture")
	view:render(case.tree)
	local actual, tree = ref.snapshot(view.engine)
	local lines = case.check_text and vim.api.nvim_buf_get_lines(win.buf, 0, -1, false)
	local drawn = vim.api.nvim_buf_get_lines(win.buf, 0, -1, false)
	view:destroy()
	win:destroy()
	local entry = {
		browser_lines = browser_layout.text and browser_layout.text.lines,
		name = case.name,
		width = case.width,
		html = ref.html(tree),
		boxes = vim.deepcopy(actual),
		lines = drawn,
	}
	shown[#shown + 1] = entry
	local ok, status, reason = pcall(ref.compare, browser_layout, actual, lines)
	entry.status = not ok and "failed" or status == "unsupported" and "skipped" or "passed"
	entry.reason = not ok and status or reason
	if not ok then
		error(status, 0)
	end
	return status, reason
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
if show then
	ref.show(shown, vim.fn.fnamemodify(".tests/browser-fixtures.html", ":p"))
end
ref.close()
assert(failures == 0, ("%d of %d browser comparisons failed"):format(failures, #cases))
