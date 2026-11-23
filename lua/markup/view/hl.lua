--- Interns highlights, so the engine only ever sees small integers.

---@class markup.view.hl
local M = {}

local ids = {} ---@type table<string, integer>
local names = {} ---@type string[]

---@param name string
local function intern(name)
	local id = ids[name]
	if not id then
		id = #names + 1
		names[id] = name
		ids[name] = id
	end
	return id
end

--- Tables define a generated group, shared by every identical table.
---@param style? string|vim.api.keyset.highlight
---@return integer
function M.id(style)
	if style == nil or style == false then
		return 0
	end

	if type(style) == "string" then
		return intern(style)
	end

	if vim.tbl_isempty(style) then
		return 0
	end

	local key = vim.inspect(style, { newline = "", indent = "" })
	local known = ids[key]
	if known then
		return known
	end

	local name = ("MarkupStyle%d"):format(#names + 1)
	local definition = vim.deepcopy(style)
	definition.fg, definition.color = definition.fg or definition.color, nil
	definition.bg, definition.background = definition.bg or definition.background, nil
	Markup.util.set_hl({ [name] = definition })

	local id = intern(name)
	ids[key] = id
	return id
end

local edges = {} ---@type table<string, string>

-- Groups canvas cells draw with, by the id of the style each comes from.
local canvas_ids = {} ---@type table<integer, integer>
-- Their names, and the style group each comes from, false for none.
local canvas_sources = {} ---@type table<string, string|false>

--- What a canvas draws takes nothing from the boxes around it, as a CSS
--- canvas's drawing takes nothing from CSS: the style's own attributes,
--- `Normal`'s foreground when it has none, and only the background under it
--- showing through.
--- A group's own definition, links followed. `link = false` would do that,
--- but can answer with a stale `Normal` once it is set again.
---@param name string
---@return vim.api.keyset.get_hl_info
local function resolve(name)
	local definition = vim.api.nvim_get_hl(0, { name = name })
	for _ = 1, 100 do
		if not definition.link then
			break
		end
		definition = vim.api.nvim_get_hl(0, { name = definition.link })
	end
	return definition
end

-- A canvas box paints only when its current group supplies a background.
local backgrounds = {}

function M.canvas_background(id, apply)
	local source = names[id]
	local previous
	local function refresh()
		local definition = source and resolve(source) or {}
		local background = (definition.bg or definition.ctermbg or definition.reverse) and id or 0
		if background ~= previous then
			previous = background
			apply(background)
		end
	end
	refresh()
	backgrounds[refresh] = source
	return function()
		backgrounds[refresh] = nil
	end
end

local function define_canvas(name, source)
	local definition = source and resolve(source) or {}
	local normal = resolve("Normal")
	definition.fg = definition.fg or normal.fg
	definition.ctermfg = definition.ctermfg or normal.ctermfg
	definition.default, definition.link = nil, nil
	definition.nocombine = true
	definition.cterm = definition.cterm or {}
	definition.cterm.nocombine = true
	vim.api.nvim_set_hl(0, name, definition)
end

local function define_edge(name, group)
	local bg = vim.api.nvim_get_hl(0, { name = group, link = false }).bg
	vim.api.nvim_set_hl(0, name, { fg = bg })
end

vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("markup.view.hl", { clear = true }),
	callback = function()
		for refresh in pairs(backgrounds) do
			refresh()
		end
		for name, group in pairs(edges) do
			define_edge(name, group)
		end
		for name, source in pairs(canvas_sources) do
			define_canvas(name, source or nil)
		end
	end,
})

--- Redraws the edge of a group whose colors just changed, such as an animated one.
---@param group string
function M.sync_edge(group)
	for refresh, source in pairs(backgrounds) do
		if source == group then
			refresh()
		end
	end
	for name, source in pairs(edges) do
		if source == group then
			define_edge(name, group)
		end
	end
	for name, source in pairs(canvas_sources) do
		if source == group or group == "Normal" then
			define_canvas(name, source or nil)
		end
	end
end

--- The group a canvas cell of style `id` draws with, `0` for no style. See
--- `define_canvas`.
---@param id integer
---@return integer
function M.canvas(id)
	local derived = canvas_ids[id]
	if derived then
		return derived
	end
	local source = id ~= 0 and names[id] or nil
	local name = source and "MarkupCanvas_" .. source:gsub("[^%w_.@-]", "_") or "MarkupCanvas"
	canvas_sources[name] = source or false
	define_canvas(name, source)
	derived = intern(name)
	canvas_ids[id] = derived
	return derived
end

--- A group drawing in the background color of `group`, for half block edges.
---@param group string
---@return string
function M.edge(group)
	local name = "MarkupEdge_" .. group:gsub("[^%w_]", "_")
	if not edges[name] then
		edges[name] = group
		define_edge(name, group)
	end
	return name
end

---@param id integer
---@return string
function M.name(id)
	return names[id]
end

return M
