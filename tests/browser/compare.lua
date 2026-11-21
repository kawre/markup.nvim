-- Run from the repository root after make build.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require("markup")

local function cells(value, unit)
	assert(type(value) == "number" and value >= 0 and value % 1 == 0, "expected a whole cell count")
	return value .. unit
end

local function tracks(value, unit)
	if type(value) == "number" then
		return ("repeat(%d, 1fr)"):format(value)
	end
	return table.concat(
		vim.tbl_map(function(track)
			if type(track) == "number" then
				return cells(track, unit)
			end
			assert(track == "auto" or track:match("^%d+fr$"), "unsupported track")
			return track
		end, value),
		" "
	)
end

local justify =
	{ start = "flex-start", center = "center", ["end"] = "flex-end", between = "space-between" }
local function style(name, value)
	if name == "width" or name == "max_width" or name == "min_width" then
		return name:gsub("_", "-") .. ":" .. cells(value, "ch")
	elseif name == "height" then
		return "height:" .. cells(value * 20, "px")
	elseif name == "columns" then
		return "grid-template-columns:" .. tracks(value, "ch")
	elseif name == "gap" then
		local row, col = value, value
		if type(value) == "table" then
			row, col = value[1], value[2]
		end
		return "gap:" .. cells(row * 20, "px") .. " " .. cells(col, "ch")
	elseif name == "justify" then
		return "justify-content:" .. assert(justify[value], "unsupported justification")
	end
	error("unsupported prop: " .. name)
end

local tags = { block = "div", inline = "span", flex = "div", grid = "div" }
local function html(node)
	if node == nil or node == false then
		return ""
	end
	if type(node) == "string" or type(node) == "number" then
		local text = tostring(node)
		assert(not text:find("[^ -~]"), "reference fixtures require printable ASCII")
		return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
	end
	assert(type(node) == "table", "expected a static element or list")
	if not node.type then
		return table.concat(vim.tbl_map(html, node))
	end
	local tag = assert(tags[node.type], "unsupported element: " .. tostring(node.type))
	local css = { "display:" .. node.type }
	for name, value in pairs(node.props) do
		if name ~= "children" then
			css[#css + 1] = style(name, value)
		end
	end
	return ("<%s style=\"%s\">%s</%s>"):format(
		tag,
		table.concat(css, ";"),
		html(node.props.children),
		tag
	)
end

local browser = vim.env.CHROME_BIN
if not browser then
	for _, name in ipairs({
		"chromium",
		"google-chrome",
		"google-chrome-stable",
		"chromium-browser",
	}) do
		if vim.fn.executable(name) == 1 then
			browser = name
			break
		end
	end
end
assert(browser, "install Chromium or set CHROME_BIN")
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
local template = table.concat(vim.fn.readfile("tests/browser/grid.html"), "\n")

local function reference(case)
	local page = template:gsub("WIDTH", tostring(case.width)):gsub("CONTENT", function()
		return html(case.tree)
	end)
	local path = directory .. "/layout.html"
	vim.fn.writefile(vim.split(page, "\n", { plain = true }), path)
	local result = vim.system({
		browser,
		"--headless",
		"--disable-gpu",
		"--no-first-run",
		"--user-data-dir=" .. directory .. "/profile",
		"--dump-dom",
		vim.uri_from_fname(path),
	}, { text = true, timeout = 20000 }):wait()
	assert(result.code == 0, result.stderr)
	local encoded =
		assert(result.stdout:match("<output>(.-)</output>"), "browser produced no result")
	assert(not encoded:match("^ERROR") and #encoded > 0, "browser measurement failed: " .. encoded)
	return vim.json.decode(vim.base64.decode(encoded))
end

local function compare(case)
	local expected = reference(case)
	local win =
		Markup.window({ width = case.width, height = 10, border = "none", backdrop = false })
	local view = Markup.view(win)
	assert(view:columns() == case.width, "Neovim viewport width differs from fixture")
	view:render(case.tree)
	local actual = vim.api.nvim_buf_get_lines(win.buf, 0, -1, false)
	view:destroy()
	win:destroy()
	for i, line in ipairs(actual) do
		actual[i] = line:gsub(" +$", "")
	end
	if not vim.deep_equal(actual, expected) then
		error(("browser %s\n  Neovim  %s"):format(vim.inspect(expected), vim.inspect(actual)), 0)
	end
end

local cases = dofile(arg[1] or "tests/browser/cases.lua")
local failures = 0
for _, case in ipairs(cases) do
	local ok, err = pcall(compare, case)
	print(("%s %s%s"):format(ok and "PASS" or "FAIL", case.name, ok and "" or "\n  " .. err))
	if not ok then
		failures = failures + 1
	end
end
vim.fn.delete(directory, "rf")
assert(failures == 0, ("%d of %d browser comparisons failed"):format(failures, #cases))
