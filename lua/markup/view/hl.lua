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

---@param id integer
---@return string
function M.name(id)
	return names[id]
end

return M
