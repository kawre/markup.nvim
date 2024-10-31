local markup = require("markup")
local log = require("markup.logger")

---@class nui_text_extmark
---@field id? integer
---@field hl_group? string
---@field [string] any

---@class markup.Text : markup.Object
---@field protected extmark? nui_text_extmark
local Text = markup.Object("MarkupText")

---@param content string|markup.Text
---@param extmark? string|nui_text_extmark highlight group name or extmark options
function Text:init(content, extmark)
	if type(content) == "string" then
		self:set(content, extmark)
	else
		-- cloning
		self:set(content._content, extmark or content.extmark)
	end
end

---@param content string text content
---@param extmark? string|nui_text_extmark highlight group name or extmark options
---@return markup.Text
function Text:set(content, extmark)
	if self._content ~= content then
		self._content = content
		self._length = vim.fn.strlen(content)
		self._width = vim.api.nvim_strwidth(content)
	end

	if extmark then
		-- preserve self.extmark.id
		local id = self.extmark and self.extmark.id or nil
		self.extmark = is_type("string", extmark) and { hl_group = extmark } or vim.deepcopy(extmark)
		self.extmark.id = id
	end

	return self
end

---@return string
function Text:content()
	return self._content
end

---@return number
function Text:length()
	return self._length
end

---@return number
function Text:width()
	return self._width
end

---@param bufnr number buffer number
---@param ns_id number namespace id
---@param linenr number line number (1-indexed)
---@param byte_start number start byte position (0-indexed)
---@return nil
function Text:highlight(bufnr, ns_id, linenr, byte_start)
	if not self.extmark then
		return
	end

	self.extmark.end_col = byte_start + self:length()

	self.extmark.id =
		vim.api.nvim_buf_set_extmark(bufnr, _.ensure_namespace_id(ns_id), linenr - 1, byte_start, self.extmark)
end

---@param renderer markup.Renderer
---@param parent? markup.Element
function Text:render(renderer, parent)
	self:draw(renderer)
	renderer:inc_pos(self:length())
end

---@param renderer markup.Renderer
function Text:draw(renderer)
	local bufnr, ns_id = renderer._.bufnr, renderer._.ns_id
	local row, col = renderer:get_pos()

	local content = self:content()
	vim.api.nvim_buf_set_text(bufnr, row, col, row, col, { content })
	self:highlight(bufnr, ns_id, row, col)
end

---@alias markup.Text.constructor fun(content: string|markup.Text, extmark?: string|nui_text_extmark): markup.Text

---@type markup.Text.constructor
local MarkupText = Text

return MarkupText
