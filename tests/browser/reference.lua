-- The folder of this file, for what it reads beside it: a test may have
-- changed the directory by the time it loads, as the playground does.
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")

--- One cell along a row and one along a column, in pixels. The page's font
--- makes every character exactly one cell wide. CSS `ch` would not do: Chrome
--- rounds it on its own, a little short of the characters.
local CELL, LINE = 10, 20

local function cells(value, unit)
	-- Whole cells, and below zero too: offsets and margins can be negative.
	assert(type(value) == "number" and value % 1 == 0, "unsupported: non-integral cell length")
	return value .. unit
end

local function tracks(value, unit)
	if type(value) == "number" then
		return ("repeat(%d, 1fr)"):format(value)
	end
	return table.concat(
		vim.tbl_map(function(track)
			if type(track) == "number" then
				return cells(track * (unit == "row" and LINE or CELL), "px")
			end
			assert(track == "auto" or track:match("^%d+fr$"), "unsupported: grid track")
			return track
		end, value),
		" "
	)
end

-- markup.nvim never pushes content past the start of its box: a terminal has
-- no column before the first. That is CSS's `safe` alignment.
local justify = {
	start = "flex-start",
	center = "safe center",
	["end"] = "safe flex-end",
	between = "space-between",
	evenly = "space-evenly",
	around = "space-around",
}
local lengths = {
	width = "col",
	height = "row",
	min_width = "col",
	max_width = "col",
	min_height = "row",
	max_height = "row",
	row_gap = "row",
	column_gap = "col",
}
for _, side in ipairs({ "top", "bottom", "left", "right" }) do
	local unit = (side == "top" or side == "bottom") and "row" or "col"
	for _, prefix in ipairs({ "padding_", "margin_", "" }) do
		lengths[prefix .. side] = unit
	end
end
local renamed = {
	direction = "flex-direction",
	align = "align-items",
	grow = "flex-grow",
	shrink = "flex-shrink",
	auto_flow = "grid-auto-flow",
	row = "grid-row-start",
	column = "grid-column-start",
	order = "order",
	align_self = "align-self",
	justify_items = "justify-items",
	justify_self = "justify-self",
	position = "position",
	z = "z-index",
	overflow = "overflow",
	overflow_x = "overflow-x",
	overflow_y = "overflow-y",
}

local function length(value, unit)
	if value == "fit" then
		return "fit-content"
	end
	if value == "full" then
		return "100%"
	end
	if value == "auto" then
		return value
	end
	if type(value) == "number" and value > 0 and value < 1 then
		-- A terminal has no part of a cell: markup.nvim rounds a share up to
		-- whole cells, which CSS `round()` does too.
		return ("round(up, %s%%, %dpx)"):format(value * 100, unit == "row" and LINE or CELL)
	end
	assert(type(value) == "number", "unsupported: length " .. tostring(value))
	if unit == "row" or unit == "col" then
		return cells(value * (unit == "row" and LINE or CELL), "px")
	end
	return cells(value, unit)
end

local function style(name, value)
	local property = name:gsub("_", "-")
	if lengths[name] then
		return property .. ":" .. length(value, lengths[name])
	elseif name == "columns" or name == "rows" then
		return "grid-template-"
			.. name
			.. ":"
			.. tracks(value, name == "columns" and "col" or "row")
	elseif name == "gap" then
		local row, col = value, value
		if type(value) == "table" then
			row, col = value[1], value[2]
		end
		return "gap:" .. length(row, "row") .. " " .. length(col, "col")
	elseif name == "justify" or name == "align_content" then
		return (name == "justify" and "justify-content:" or "align-content:")
			.. (justify[value] or value)
	elseif name == "white_space" then
		return "white-space:" .. (value == "nowrap" and "pre" or "pre-wrap")
	elseif name == "wrap" then
		return "flex-wrap:" .. (value and "wrap" or "nowrap")
	elseif name == "row_span" or name == "column_span" then
		return "grid-" .. name:match("^%a+") .. "-end:span " .. value
	elseif renamed[name] then
		local aligns = name == "align" or name == "align_self" or name:match("^justify_")
		if aligns and (value == "center" or value == "end") then
			value = "safe " .. value
		end
		return renamed[name] .. ":" .. value
	end
	error("unsupported: prop " .. name)
end

-- What the translation adds is marked `data-line`: it takes no place in paths.
local STRUT = "<span data-line style=\"display:inline-block\"></span>"

local function sized_inline(props)
	return (
		(props.width or "auto") ~= "auto"
		or (props.height or "auto") ~= "auto"
		or (props.min_width or "auto") ~= "auto"
		or (props.max_width or "auto") ~= "auto"
	)
end

--- Text that is empty, or an inline holding only such text.
local function is_blank(child)
	if child == "" then
		return true
	end
	if type(child) ~= "table" or child.type ~= "inline" or sized_inline(child.props) then
		return false
	end
	local inner = child.props.children
	if type(inner) ~= "table" or inner.type then
		return inner == ""
	end
	for _, grandchild in ipairs(inner) do
		if not is_blank(grandchild) then
			return false
		end
	end
	return #inner > 0
end

local function is_inline(child)
	return type(child) ~= "table" or child.type == "inline" or not child.type
end

local tags = { block = "div", inline = "span", flex = "div", grid = "div", canvas = "div" }
local escape_widths
--- Runs of code points of one width, as the page's font has them: Neovim's
--- widths with the options it starts with.
local font_widths = vim.json.decode(table.concat(vim.fn.readfile(here .. "/cell-widths.json"), ""))

local function font_width(code)
	local low, high = 1, #font_widths
	while low <= high do
		local middle = math.floor((low + high) / 2)
		local run = font_widths[middle]
		if code < run[1] then
			high = middle - 1
		elseif code > run[2] then
			low = middle + 1
		else
			return run[3]
		end
	end
	return 1
end

--- Escapes text for HTML. Where the test's options make a character wider or
--- narrower than the font, as `ambiwidth` and `setcellwidths()` do, letter
--- spacing makes up the difference, which leaves where lines break alone.
function escape_widths(text)
	local custom = vim.o.ambiwidth ~= "single" or #vim.fn.getcellwidths() > 0
	local parts = {}
	for character in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		local escaped = character:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
		if custom and #character > 1 then
			local width = vim.fn.strdisplaywidth(character)
			if vim.fn.strdisplaywidth("a" .. character) == 1 then
				width = 0
			end
			local difference = width - font_width(vim.fn.char2nr(character))
			if difference ~= 0 then
				escaped = ("<span style=\"letter-spacing:%dpx\">%s</span>"):format(
					difference * CELL,
					escaped
				)
			end
		end
		parts[#parts + 1] = escaped
	end
	return table.concat(parts)
end

local render_children

local function html(node, profile)
	if node == nil or node == false then
		return ""
	end
	if type(node) == "string" or type(node) == "number" then
		local text = tostring(node)
		if text == "" then
			-- Only a line when nothing else is, see `render_children`.
			return ""
		end
		-- As markup.nvim draws it: bytes that are not UTF-8 replaced, and a
		-- tab four spaces wherever it lands, a convention of its own.
		text = require("markup.view.protocol").valid_utf8(text):gsub("\t", "    ")
		return escape_widths(text)
	end
	assert(type(node) == "table", "expected a static element or list")
	if not node.type then
		local children = {}
		for i, child in ipairs(node) do
			children[i] = html(child, profile)
		end
		return table.concat(children)
	end
	local tag = assert(tags[node.type], "unsupported element: " .. tostring(node.type))
	local props = node.props
	local display = node.type == "canvas" and "block" or node.type
	if display == "inline" and sized_inline(props) then
		-- markup.nvim sizes an inline that has a width; CSS sizes only an
		-- inline-block.
		display = "inline-block"
	end
	local css = { "display:" .. display }
	if
		profile
		and (
			node.type == "canvas"
			or props.border_sides
			or props.border_cells
			or (props.overflow or "visible") ~= "visible"
			or (props.overflow_x or "visible") ~= "visible"
			or (props.overflow_y or "visible") ~= "visible"
			or props.position == "absolute"
		)
	then
		-- DOM ranges omit border glyphs and include clipped or occluded text.
		profile.check_text = false
	end
	local children = node.props.children
	local names = vim.tbl_keys(node.props)
	table.sort(names)
	for _, name in ipairs(names) do
		local value = node.props[name]
		if name == "border_sides" then
			for _, side in ipairs(value) do
				local width = (side == "top" or side == "bottom") and LINE .. "px" or CELL .. "px"
				css[#css + 1] = "border-" .. side .. ":" .. width .. " solid"
			end
		elseif name == "border_cells" then
			-- `{ top, right, bottom, left }`, in cells.
			for i, side in ipairs({ "top", "right", "bottom", "left" }) do
				if value[i] > 0 then
					local unit = (side == "top" or side == "bottom") and LINE or CELL
					css[#css + 1] = ("border-%s:%dpx solid"):format(side, value[i] * unit)
				end
			end
		elseif name == "reverse" and node.type == "flex" then
			if value then
				css[#css + 1] = "flex-direction:" .. (props.direction or "row") .. "-reverse"
			end
		elseif name == "spacing" and node.type ~= "flex" and node.type ~= "grid" then
			-- Spacers between the children, see `render_children`.
		elseif name == "spacing" then
			css[#css + 1] = "row-gap:" .. length(math.max(value, props.row_gap or 0), "row")
			css[#css + 1] = "column-gap:" .. length(math.max(value, props.column_gap or 0), "col")
		elseif name ~= "children" then
			css[#css + 1] = style(name, value)
		end
	end
	local inner = render_children(node, children, profile)
	return ("<%s style=\"%s\">%s</%s>"):format(tag, table.concat(css, ";"), inner, tag)
end

--- The children of an element. A markup.nvim convention that CSS has not: a
--- run of inline content that is only empty text is still a line, as
--- `m.block("")` makes a blank one. In a flex or grid, text is as in CSS.
function render_children(node, children, profile)
	if type(children) ~= "table" or children.type then
		children = { children }
	end
	local items = node.type == "flex" or node.type == "grid"
	local spacing = not items and node.props.spacing or 0
	if node.type == "inline" and spacing > 0 then
		-- Spacing between the children of an inline, in cells.
		local spacer = ("<span data-line style=\"display:inline-block;width:%dpx\"></span>"):format(
			spacing * CELL
		)
		local parts = {}
		for _, child in ipairs(children) do
			parts[#parts + 1] = html(child, profile)
		end
		return table.concat(parts, spacer)
	end
	-- Each row: a run of inline content, or a block.
	local rows, run = {}, {}
	local function flush()
		if #run == 0 then
			return
		end
		local blank = true
		local parts = {}
		for _, child in ipairs(run) do
			blank = blank and is_blank(child)
			parts[#parts + 1] = html(child, profile)
		end
		if blank and not items then
			table.insert(parts, 1, STRUT)
		end
		rows[#rows + 1] = table.concat(parts)
		run = {}
	end
	for _, child in ipairs(children) do
		if is_inline(child) and not items then
			run[#run + 1] = child
		else
			flush()
			rows[#rows + 1] = html(child, profile)
		end
	end
	flush()
	-- markup.nvim's `spacing` in a block: a row of its own between rows.
	local spacer = spacing > 0
			and ("<div data-line style=\"display:block;height:%dpx\"></div>"):format(spacing * LINE)
		or ""
	return table.concat(rows, spacer)
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
local directory
local template = table.concat(vim.fn.readfile(here .. "/grid.html"), "\n")
local font = (function()
	local file = assert(io.open(here .. "/cell.ttf", "rb"))
	local bytes = file:read("*a")
	file:close()
	return vim.base64.encode(bytes)
end)()
template = template:gsub("FONT", function()
	return font
end)

local function batch(cases)
	assert(browser, "install Chromium or set CHROME_BIN")
	if not directory then
		directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
	end
	local fixtures = {}
	for _, case in ipairs(cases) do
		assert(case.width > 0 and case.width % 1 == 0, "invalid viewport width")
		fixtures[#fixtures + 1] = ("<main style=\"position:absolute;left:0;top:0;width:%dpx\" data-columns=\"%d\"%s>%s</main>"):format(
			case.width * CELL,
			case.width,
			-- With SHOW, the text is measured too, to show it, compared or not.
			(case.check_text or (vim.env.SHOW or "") ~= "") and " data-text" or "",
			case.html or html(case.tree)
		)
	end
	local page = template:gsub("FIXTURES", function()
		return table.concat(fixtures)
	end)
	local path = directory .. "/layout.html"
	vim.fn.writefile(vim.split(page, "\n", { plain = true }), path)
	local result = vim.system({
		browser,
		"--headless",
		"--disable-gpu",
		"--no-first-run",
		"--user-data-dir=" .. directory .. "/profile",
		-- Long enough for the font to load before the page is read.
		"--virtual-time-budget=10000",
		"--dump-dom",
		vim.uri_from_fname(path),
	}, { text = true, timeout = 20000 }):wait()
	assert(result.code == 0, result.stderr)
	local encoded =
		assert(result.stdout:match("<output>(.-)</output>"), "browser produced no result")
	assert(not encoded:match("^ERROR") and #encoded > 0, "browser measurement failed: " .. encoded)
	return vim.json.decode(vim.base64.decode(encoded))
end

-- Match authored elements by their path among element siblings. Text nodes
-- participate in layout but do not occupy a path component.
local function snapshot(engine, styles, text)
	local boxes = {}
	local limit = engine:node_count()
	local function visit(id, path, content)
		local index = 0
		for _, child in ipairs(engine:children(id, 0, limit, true)) do
			if child.display == "text" then
				content[#content + 1] = text
						and assert(text[child.id], "missing input for text node " .. child.id)
					or child.text
			else
				index = index + 1
				local child_path = path .. "/" .. index
				if child.display ~= "inline" then
					local top, right, bottom, left = unpack(child.margin)
					boxes[#boxes + 1] = {
						path = child_path,
						display = child.display == "canvas" and "block" or child.display,
						rect = {
							child.x + left,
							child.y + top,
							child.outer_width - left - right,
							child.outer_height - top - bottom,
						},
					}
				end
				local children = {}
				local props = vim.tbl_extend(
					"force",
					styles and styles[child.id] or {},
					{ children = children }
				)
				-- The cells the engine gives the border on each side, whatever
				-- its characters: some draw only some sides.
				props.border_sides = nil
				local edges = child.border
				if edges and (edges[1] + edges[2] + edges[3] + edges[4]) > 0 then
					props.border_cells = edges
				end
				content[#content + 1] = { type = child.display, props = props }
				if child.children > 0 then
					visit(child.id, child_path, children)
				end
			end
		end
	end
	local root = engine:describe(require("markup.view.protocol").ROOT)
	local content = {}
	visit(root.id, "", content)
	return boxes, content
end

local function compare(browser_layout, actual, lines)
	local expected = browser_layout.boxes
	assert(#actual == #expected, ("expected %d boxes, found %d"):format(#expected, #actual))
	-- A terminal has no part of a cell. Where the browser gives one, such as
	-- half of an odd space centered or a fraction's share, markup.nvim's
	-- whole cells match it when they are within a cell of it.
	for i, box in ipairs(expected) do
		for j, value in ipairs(box.rect) do
			local rounded = math.floor(value + 0.5)
			if math.abs(value - rounded) <= 0.025 then
				box.rect[j] = rounded
			elseif actual[i] and math.abs(actual[i].rect[j] - value) < 1 then
				box.rect[j] = actual[i].rect[j]
			end
		end
	end
	for i, box in ipairs(expected) do
		if not vim.deep_equal(box, actual[i]) then
			error(
				("at %s (%s), expected %s, got %s at %s (%s) [x, y, width, height]"):format(
					box.path,
					box.display,
					vim.inspect(box.rect),
					vim.inspect(actual[i].rect),
					actual[i].path,
					actual[i].display
				),
				0
			)
		end
	end
	if lines then
		local text = browser_layout.text
		if text.unsupported then
			return "unsupported", text.unsupported
		end
		-- Rows past the end that hold nothing, such as below an empty box that
		-- reaches down, look the same as no rows.
		local function trim(rows)
			local last = #rows
			while last > 0 and (rows[last] or ""):match("^ *$") do
				last = last - 1
			end
			return last
		end
		for row = 1, math.max(trim(lines), trim(text.lines)) do
			local actual_line = lines[row] and lines[row]:gsub(" +$", "")
			local browser_line = text.lines[row] and text.lines[row]:gsub(" +$", "")
			if actual_line ~= browser_line then
				error(
					("text row %d: browser %s, Neovim %s"):format(
						row,
						vim.inspect(browser_line),
						vim.inspect(actual_line)
					),
					0
				)
			end
		end
	end
end

--- Escapes text for an HTML attribute or element.
local function escape(text)
	return (
		tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\"", "&quot;")
	)
end

--- Writes a page that shows each frame as the browser lays it out, with the
--- boxes markup.nvim laid out over it and the lines Neovim drew beside it, and
--- opens it. `entries` hold `name`, `status` ("failed", "passed" or
--- "skipped"), `reason`, `html`, `width`, `boxes` and `lines`.
local function show(entries, path)
	local style = template:match("<style>(.-)</style>")
	local order = { failed = 1, skipped = 2, passed = 3 }
	table.sort(entries, function(a, b)
		return (order[a.status] or 4) < (order[b.status] or 4)
	end)
	local counts = { failed = 0, skipped = 0, passed = 0 }
	local sections = {}
	for _, entry in ipairs(entries) do
		counts[entry.status] = (counts[entry.status] or 0) + 1
		local wrong = entry.status == "failed"
			and tostring(entry.reason or ""):match("^at (%S+) %(")
		local rows = #(entry.lines or {})
		local overlay = {}
		for _, box in ipairs(entry.boxes or {}) do
			local x, y, w, h = unpack(box.rect)
			rows = math.max(rows, y + h)
			overlay[#overlay + 1] = ("<div class=\"box%s\" title=\"%s %s: %s\" style=\"left:%dpx;top:%dpx;width:%dpx;height:%dpx\"></div>"):format(
				box.path == wrong and " wrong" or "",
				escape(box.path),
				escape(box.display),
				escape(table.concat(box.rect, ", ")),
				x * CELL,
				y * LINE,
				math.max(w * CELL, 1),
				math.max(h * LINE, 1)
			)
		end
		local width = (entry.width or 60) * CELL
		sections[#sections + 1] = ([[
<section class="%s">
  <h2><span class="tag">%s</span> %s</h2>
  %s
  <div class="row">
    <figure><figcaption>Chromium, markup.nvim's boxes over it</figcaption>
      <div class="frame%s" style="width:%dpx;height:%dpx"><main style="position:absolute;left:0;top:0;width:%dpx">%s</main>%s<div class="overlay">%s</div></div>
    </figure>
    <figure><figcaption>Neovim</figcaption><pre class="frame nvim" style="width:%dpx">%s</pre></figure>
  </div>
</section>]]):format(
			entry.status,
			entry.status,
			escape(entry.name),
			entry.reason and ("<p class=\"reason\">%s</p>"):format(escape(entry.reason)) or "",
			entry.browser_lines and " readable" or "",
			width,
			math.max(rows, #(entry.browser_lines or {}), 1) * LINE,
			width,
			entry.html or "",
			entry.browser_lines
					and ("<pre class=\"text\">%s</pre>"):format(
						escape(table.concat(entry.browser_lines, "\n"))
					)
				or "",
			table.concat(overlay),
			width,
			escape(table.concat(entry.lines or {}, "\n"))
		)
	end
	local page = ([[<!doctype html>
<meta charset="utf-8">
<title>markup.nvim against Chromium</title>
<style>%s
  body { margin: 16px; background: #11111b; color: #cdd6f4; }
  header, h2, figcaption, .reason { font: 14px/1.4 system-ui, sans-serif; }
  header { position: sticky; top: 0; background: #11111b; padding: 8px 0; z-index: 2; }
  section { margin: 0 0 24px; padding: 12px; border-radius: 8px; background: #181825; }
  section.failed { box-shadow: inset 4px 0 #f38ba8; }
  section.skipped { box-shadow: inset 4px 0 #f9e2af; }
  section.passed { box-shadow: inset 4px 0 #a6e3a1; }
  h2 { margin: 0 0 6px; font-size: 13px; font-weight: 600; }
  .tag { text-transform: uppercase; font-size: 11px; opacity: .7; }
  .reason { margin: 0 0 8px; color: #f38ba8; }
  .row { display: flex; gap: 24px; align-items: flex-start; flex-wrap: wrap; }
  figure { margin: 0; }
  figcaption { opacity: .6; margin-bottom: 4px; font-size: 12px; }
  .frame { position: relative; background: #1e1e2e; color: #cdd6f4; outline: 1px solid #45475a; overflow: visible; }
  .frame main { color: #cdd6f4; }
  .overlay { position: absolute; inset: 0; pointer-events: none; }
  .box { position: absolute; outline: 1px dashed #a6e3a1; }
  .box.wrong { outline: 2px solid #f38ba8; background: #f38ba822; }
  /* The page's font draws each character as a box, which lays out as Neovim
     measures; where the browser's text is known, it is shown over it in a
     font that can be read, about as wide. */
  .frame.readable main { color: transparent; }
  pre.text, pre.nvim { margin: 0; white-space: pre; min-height: 20px;
    font: 20px/20px monospace; font-size-adjust: ch-width 0.5; }
  pre.text { position: absolute; left: 0; top: 0; pointer-events: none; }
  .hide-passed section.passed { display: none; }
</style>
<header>%d failed, %d skipped, %d passed.
  <label><input type="checkbox" %s onchange="document.body.classList.toggle('hide-passed', this.checked)"> Hide what passed</label>
  Hover a box for its path and cells.</header>
<body class="%s">
%s
</body>]]):format(
		style,
		counts.failed,
		counts.skipped,
		counts.passed,
		-- What passed only gets in the way while something differs.
		counts.failed > 0 and "checked" or "",
		counts.failed > 0 and "hide-passed" or "",
		table.concat(sections, "\n")
	)
	vim.fn.writefile(vim.split(page, "\n", { plain = true }), path)
	vim.ui.open(path)
	print("opened " .. path)
end

return {
	unsupported = function(err)
		return tostring(err):find("unsupported: ", 1, true) ~= nil
	end,
	html = html,
	snapshot = snapshot,
	batch = batch,
	reference = function(case)
		return batch({ case })[1]
	end,
	compare = compare,
	show = show,
	close = function()
		if directory then
			vim.fn.delete(directory, "rf")
		end
	end,
}
