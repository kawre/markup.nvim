--- One cell along a row and one along a column, in pixels. The page's font
--- makes every character exactly one cell wide. CSS `ch` would not do: Chrome
--- rounds it on its own, a little short of the characters.
local CELL, LINE = 10, 20

local function cells(value, unit)
	assert(
		type(value) == "number" and value >= 0 and value % 1 == 0,
		"unsupported: non-integral cell length"
	)
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
		return (value * 100) .. "%"
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

--- Text that is empty, or an inline holding only such text.
local function is_blank(child)
	if child == "" then
		return true
	end
	if type(child) ~= "table" or child.type ~= "inline" then
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

local tags = { block = "div", inline = "span", flex = "div", grid = "div" }
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
		assert(not text:find("[^ -~]"), "unsupported: text outside printable ASCII")
		return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
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
	local display = node.type
	if
		display == "inline"
		and (props.width or props.min_width or props.max_width or props.height)
	then
		-- markup.nvim sizes an inline that has a width; CSS sizes only an
		-- inline-block.
		display = "inline-block"
	end
	local css = { "display:" .. display }
	if
		profile
		and (
			props.border_sides
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
		elseif name == "spacing" and (node.type == "flex" or node.type == "grid") then
			css[#css + 1] = "row-gap:" .. length(math.max(value, props.row_gap or 0), "row")
			css[#css + 1] = "column-gap:" .. length(math.max(value, props.column_gap or 0), "col")
		elseif name ~= "children" then
			css[#css + 1] = style(name, value)
		end
	end
	local inner = render_children(node, children, profile)
	return ("<%s style=\"%s\">%s</%s>"):format(tag, table.concat(css, ";"), inner, tag)
end

--- The children of an element. Two markup.nvim conventions that CSS has not:
--- a run of inline content that is only empty text is still a line, as
--- `m.block("")` makes a blank one, and each text of a flex or grid is an
--- item of its own, where CSS would join neighbouring text into one.
function render_children(node, children, profile)
	if type(children) ~= "table" or children.type then
		children = { children }
	end
	local items = node.type == "flex" or node.type == "grid"
	local parts, run = {}, {}
	local function flush()
		if #run == 0 then
			return
		end
		local blank = true
		for _, child in ipairs(run) do
			blank = blank and is_blank(child)
		end
		if blank and not items then
			parts[#parts + 1] = STRUT
		end
		for _, child in ipairs(run) do
			parts[#parts + 1] = html(child, profile)
		end
		run = {}
	end
	for _, child in ipairs(children) do
		if items and (type(child) == "string" or type(child) == "number") then
			parts[#parts + 1] = "<span data-line>"
				.. (child == "" and STRUT or html(child, profile))
				.. "</span>"
		elseif is_inline(child) and not items then
			run[#run + 1] = child
		else
			flush()
			parts[#parts + 1] = html(child, profile)
		end
	end
	flush()
	return table.concat(parts)
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
local template = table.concat(vim.fn.readfile("tests/browser/grid.html"), "\n")
local font = (function()
	local file = assert(io.open("tests/browser/cell.ttf", "rb"))
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
			case.check_text and " data-text" or "",
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
						display = child.display,
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
	for _, box in ipairs(expected) do
		for j, value in ipairs(box.rect) do
			local rounded = math.floor(value + 0.5)
			if math.abs(value - rounded) > 0.025 then
				return "unsupported",
					("box %s has fractional geometry %s"):format(box.path, vim.inspect(box.rect))
			end
			box.rect[j] = rounded
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
			if actual_line ~= text.lines[row] then
				error(
					("text row %d: browser %s, Neovim %s"):format(
						row,
						vim.inspect(text.lines[row]),
						vim.inspect(actual_line)
					),
					0
				)
			end
		end
	end
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
	close = function()
		if directory then
			vim.fn.delete(directory, "rf")
		end
	end,
}
