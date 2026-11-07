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

local function define_edge(name, group)
	local bg = vim.api.nvim_get_hl(0, { name = group, link = false }).bg
	vim.api.nvim_set_hl(0, name, { fg = bg })
end

vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("markup.view.hl", { clear = true }),
	callback = function()
		for name, group in pairs(edges) do
			define_edge(name, group)
		end
	end,
})

--- Redraws the edge of a group whose colors just changed, such as an animated one.
---@param group string
function M.sync_edge(group)
	for name, source in pairs(edges) do
		if source == group then
			define_edge(name, group)
		end
	end
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
