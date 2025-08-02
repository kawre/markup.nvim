local ts = vim.treesitter

---@alias markup.parser.lang string | "html" | "markdown"

---@class markup.parser.impl
---@field lang string
---@field parse_node fun(parser: markup.parser, node: TSNode): markup.element
---@field prepare_text fun(text: string): string
---@field get_node_text fun(node: TSNode): string

---@class markup.parser.node
---@field type string
---@field parent markup.element

---@class markup.parser
---@field impl markup.parser.impl
---@field lang string
---@field text string
---@overload fun(text: string, lang: markup.parser.lang|markup.parser.impl): markup.parser
local M = Markup.object()

local parsers = {
	html = require("markup.parser.html"),
	markdown = require("markup.parser.md"),
}

---@param text string
---@param lang markup.parser.lang|markup.parser.impl
function M:new(text, lang)
	if type(lang) == "table" then
		---@cast lang markup.parser.impl
		self.impl = lang
		self.lang = lang.lang or "html"
	else
		---@cast lang string
		self.impl = parsers[lang] or parsers.html
		self.lang = lang
	end
	self.text = text
end

function M:parse()
	self.text = self.impl.prepare_text(self.text)
	local tree = ts.get_string_parser(self.text, self.lang)
	self.tree = tree
	local root = tree:parse()[1]:root()
	return self:parse_node(root)
end

function M:get_node_text(node)
	return ts.get_node_text(node, self.text)
end

---@param node TSNode
---@return markup.element
function M:parse_node(node)
	return self.impl.parse_node(self, node)
end

---@class markup.Parser.constructor
---@field lang string
---@field text string

---@type markup.Parser.constructor
return M
