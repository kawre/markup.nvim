local markup = require("markup.core")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local ts = vim.treesitter

---@class markup.Parser.node
---@field type string
---@field parent markup.Element

---@class markup.Parser : markup.Object
local Parser = markup.Object("markup.parser")

function Parser:init(text, lang)
	self.lang = lang
	self.text = text
end

function Parser:parse()
	local parser = ts.get_string_parser(self.text, self.lang)
	self.parser = parser
	local root = parser:parse()[1]:root()

	return self:parse_node(root)
end

function Parser:get_node_text(node)
	return ts.get_node_text(node, self.text)
end

---@param node TSNode
---@return markup.Element
function Parser:parse_node(node)
	error("Not implemented")
end

---@class markup.Parser.constructor
---@field lang string
---@field text string

---@type markup.Parser.constructor
return Parser
